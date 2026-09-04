// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'player_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PlayerState {
  SongsTableData? get currentSong;
  bool get isPlaying;
  Duration get position;
  Duration get duration;
  bool get isShuffle;
  PlayerRepeatMode get repeatMode;
  List<SongsTableData> get queue;
  int get currentIndex;
  bool get isExpanded;
  Color? get dominantColor;
  Duration? get sleepTimerRemaining;
  List<LyricsLine> get lyrics;
  LyricsSource get lyricsSource;
  bool get isLoadingLyrics;
  bool get isLyricsVisible;
  bool get isQueueVisible;
  EqPreset get eqPreset;
  bool get isEqEnabled;
  bool get isVirtualizerEnabled;
  double get virtualizerStrength;
  bool get isDynamicsEnabled;
  DynamicsPreset get dynamicsPreset;
  HeadphoneProfile? get selectedHeadphoneProfile;
  bool get isSpatializerSupported;
  bool get isSpatializerEnabled;
  double get volumeBoost;
  bool get isCrossfeedEnabled;
  double get crossfeedDelayUs;
  double get crossfeedFeedDb;
  bool get isLimiterEnabled;
  double get limiterThresholdDb;
  double get limiterReleaseMs;
  bool get isReverbEnabled;
  int get reverbPreset;
  double get reverbWetDry;
  double get stereoBalance;
  bool get monoMix;
  bool get isSincResamplerEnabled;
  bool get hasOemAudio;
  List<String> get detectedOemEngines;
  int get activeQueueSlot;
  double get playbackSpeed;
  int? get audioSessionId;
  String? get errorMessage;

  /// Create a copy of PlayerState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $PlayerStateCopyWith<PlayerState> get copyWith =>
      _$PlayerStateCopyWithImpl<PlayerState>(this as PlayerState, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is PlayerState &&
            (identical(other.currentSong, currentSong) ||
                other.currentSong == currentSong) &&
            (identical(other.isPlaying, isPlaying) ||
                other.isPlaying == isPlaying) &&
            (identical(other.position, position) ||
                other.position == position) &&
            (identical(other.duration, duration) ||
                other.duration == duration) &&
            (identical(other.isShuffle, isShuffle) ||
                other.isShuffle == isShuffle) &&
            (identical(other.repeatMode, repeatMode) ||
                other.repeatMode == repeatMode) &&
            const DeepCollectionEquality().equals(other.queue, queue) &&
            (identical(other.currentIndex, currentIndex) ||
                other.currentIndex == currentIndex) &&
            (identical(other.isExpanded, isExpanded) ||
                other.isExpanded == isExpanded) &&
            (identical(other.dominantColor, dominantColor) ||
                other.dominantColor == dominantColor) &&
            (identical(other.sleepTimerRemaining, sleepTimerRemaining) ||
                other.sleepTimerRemaining == sleepTimerRemaining) &&
            const DeepCollectionEquality().equals(other.lyrics, lyrics) &&
            (identical(other.lyricsSource, lyricsSource) ||
                other.lyricsSource == lyricsSource) &&
            (identical(other.isLoadingLyrics, isLoadingLyrics) ||
                other.isLoadingLyrics == isLoadingLyrics) &&
            (identical(other.isLyricsVisible, isLyricsVisible) ||
                other.isLyricsVisible == isLyricsVisible) &&
            (identical(other.isQueueVisible, isQueueVisible) ||
                other.isQueueVisible == isQueueVisible) &&
            (identical(other.eqPreset, eqPreset) ||
                other.eqPreset == eqPreset) &&
            (identical(other.isEqEnabled, isEqEnabled) ||
                other.isEqEnabled == isEqEnabled) &&
            (identical(other.isVirtualizerEnabled, isVirtualizerEnabled) ||
                other.isVirtualizerEnabled == isVirtualizerEnabled) &&
            (identical(other.virtualizerStrength, virtualizerStrength) ||
                other.virtualizerStrength == virtualizerStrength) &&
            (identical(other.isDynamicsEnabled, isDynamicsEnabled) ||
                other.isDynamicsEnabled == isDynamicsEnabled) &&
            (identical(other.dynamicsPreset, dynamicsPreset) ||
                other.dynamicsPreset == dynamicsPreset) &&
            (identical(other.selectedHeadphoneProfile, selectedHeadphoneProfile) ||
                other.selectedHeadphoneProfile == selectedHeadphoneProfile) &&
            (identical(other.isSpatializerSupported, isSpatializerSupported) ||
                other.isSpatializerSupported == isSpatializerSupported) &&
            (identical(other.isSpatializerEnabled, isSpatializerEnabled) ||
                other.isSpatializerEnabled == isSpatializerEnabled) &&
            (identical(other.volumeBoost, volumeBoost) ||
                other.volumeBoost == volumeBoost) &&
            (identical(other.isCrossfeedEnabled, isCrossfeedEnabled) ||
                other.isCrossfeedEnabled == isCrossfeedEnabled) &&
            (identical(other.crossfeedDelayUs, crossfeedDelayUs) ||
                other.crossfeedDelayUs == crossfeedDelayUs) &&
            (identical(other.crossfeedFeedDb, crossfeedFeedDb) ||
                other.crossfeedFeedDb == crossfeedFeedDb) &&
            (identical(other.isLimiterEnabled, isLimiterEnabled) ||
                other.isLimiterEnabled == isLimiterEnabled) &&
            (identical(other.limiterThresholdDb, limiterThresholdDb) ||
                other.limiterThresholdDb == limiterThresholdDb) &&
            (identical(other.limiterReleaseMs, limiterReleaseMs) ||
                other.limiterReleaseMs == limiterReleaseMs) &&
            (identical(other.isReverbEnabled, isReverbEnabled) ||
                other.isReverbEnabled == isReverbEnabled) &&
            (identical(other.reverbPreset, reverbPreset) ||
                other.reverbPreset == reverbPreset) &&
            (identical(other.reverbWetDry, reverbWetDry) ||
                other.reverbWetDry == reverbWetDry) &&
            (identical(other.stereoBalance, stereoBalance) ||
                other.stereoBalance == stereoBalance) &&
            (identical(other.monoMix, monoMix) || other.monoMix == monoMix) &&
            (identical(other.isSincResamplerEnabled, isSincResamplerEnabled) ||
                other.isSincResamplerEnabled == isSincResamplerEnabled) &&
            (identical(other.hasOemAudio, hasOemAudio) ||
                other.hasOemAudio == hasOemAudio) &&
            const DeepCollectionEquality()
                .equals(other.detectedOemEngines, detectedOemEngines) &&
            (identical(other.activeQueueSlot, activeQueueSlot) ||
                other.activeQueueSlot == activeQueueSlot) &&
            (identical(other.playbackSpeed, playbackSpeed) ||
                other.playbackSpeed == playbackSpeed) &&
            (identical(other.audioSessionId, audioSessionId) || other.audioSessionId == audioSessionId) &&
            (identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
  }

  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        currentSong,
        isPlaying,
        position,
        duration,
        isShuffle,
        repeatMode,
        const DeepCollectionEquality().hash(queue),
        currentIndex,
        isExpanded,
        dominantColor,
        sleepTimerRemaining,
        const DeepCollectionEquality().hash(lyrics),
        lyricsSource,
        isLoadingLyrics,
        isLyricsVisible,
        isQueueVisible,
        eqPreset,
        isEqEnabled,
        isVirtualizerEnabled,
        virtualizerStrength,
        isDynamicsEnabled,
        dynamicsPreset,
        selectedHeadphoneProfile,
        isSpatializerSupported,
        isSpatializerEnabled,
        volumeBoost,
        isCrossfeedEnabled,
        crossfeedDelayUs,
        crossfeedFeedDb,
        isLimiterEnabled,
        limiterThresholdDb,
        limiterReleaseMs,
        isReverbEnabled,
        reverbPreset,
        reverbWetDry,
        stereoBalance,
        monoMix,
        isSincResamplerEnabled,
        hasOemAudio,
        const DeepCollectionEquality().hash(detectedOemEngines),
        activeQueueSlot,
        playbackSpeed,
        audioSessionId,
        errorMessage
      ]);

  @override
  String toString() {
    return 'PlayerState(currentSong: $currentSong, isPlaying: $isPlaying, position: $position, duration: $duration, isShuffle: $isShuffle, repeatMode: $repeatMode, queue: $queue, currentIndex: $currentIndex, isExpanded: $isExpanded, dominantColor: $dominantColor, sleepTimerRemaining: $sleepTimerRemaining, lyrics: $lyrics, lyricsSource: $lyricsSource, isLoadingLyrics: $isLoadingLyrics, isLyricsVisible: $isLyricsVisible, isQueueVisible: $isQueueVisible, eqPreset: $eqPreset, isEqEnabled: $isEqEnabled, isVirtualizerEnabled: $isVirtualizerEnabled, virtualizerStrength: $virtualizerStrength, isDynamicsEnabled: $isDynamicsEnabled, dynamicsPreset: $dynamicsPreset, selectedHeadphoneProfile: $selectedHeadphoneProfile, isSpatializerSupported: $isSpatializerSupported, isSpatializerEnabled: $isSpatializerEnabled, volumeBoost: $volumeBoost, isCrossfeedEnabled: $isCrossfeedEnabled, crossfeedDelayUs: $crossfeedDelayUs, crossfeedFeedDb: $crossfeedFeedDb, isLimiterEnabled: $isLimiterEnabled, limiterThresholdDb: $limiterThresholdDb, limiterReleaseMs: $limiterReleaseMs, isReverbEnabled: $isReverbEnabled, reverbPreset: $reverbPreset, reverbWetDry: $reverbWetDry, stereoBalance: $stereoBalance, monoMix: $monoMix, isSincResamplerEnabled: $isSincResamplerEnabled, hasOemAudio: $hasOemAudio, detectedOemEngines: $detectedOemEngines, activeQueueSlot: $activeQueueSlot, playbackSpeed: $playbackSpeed, audioSessionId: $audioSessionId, errorMessage: $errorMessage)';
  }
}

/// @nodoc
abstract mixin class $PlayerStateCopyWith<$Res> {
  factory $PlayerStateCopyWith(
          PlayerState value, $Res Function(PlayerState) _then) =
      _$PlayerStateCopyWithImpl;
  @useResult
  $Res call(
      {SongsTableData? currentSong,
      bool isPlaying,
      Duration position,
      Duration duration,
      bool isShuffle,
      PlayerRepeatMode repeatMode,
      List<SongsTableData> queue,
      int currentIndex,
      bool isExpanded,
      Color? dominantColor,
      Duration? sleepTimerRemaining,
      List<LyricsLine> lyrics,
      LyricsSource lyricsSource,
      bool isLoadingLyrics,
      bool isLyricsVisible,
      bool isQueueVisible,
      EqPreset eqPreset,
      bool isEqEnabled,
      bool isVirtualizerEnabled,
      double virtualizerStrength,
      bool isDynamicsEnabled,
      DynamicsPreset dynamicsPreset,
      HeadphoneProfile? selectedHeadphoneProfile,
      bool isSpatializerSupported,
      bool isSpatializerEnabled,
      double volumeBoost,
      bool isCrossfeedEnabled,
      double crossfeedDelayUs,
      double crossfeedFeedDb,
      bool isLimiterEnabled,
      double limiterThresholdDb,
      double limiterReleaseMs,
      bool isReverbEnabled,
      int reverbPreset,
      double reverbWetDry,
      double stereoBalance,
      bool monoMix,
      bool isSincResamplerEnabled,
      bool hasOemAudio,
      List<String> detectedOemEngines,
      int activeQueueSlot,
      double playbackSpeed,
      int? audioSessionId,
      String? errorMessage});
}

/// @nodoc
class _$PlayerStateCopyWithImpl<$Res> implements $PlayerStateCopyWith<$Res> {
  _$PlayerStateCopyWithImpl(this._self, this._then);

  final PlayerState _self;
  final $Res Function(PlayerState) _then;

  /// Create a copy of PlayerState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? currentSong = freezed,
    Object? isPlaying = null,
    Object? position = null,
    Object? duration = null,
    Object? isShuffle = null,
    Object? repeatMode = null,
    Object? queue = null,
    Object? currentIndex = null,
    Object? isExpanded = null,
    Object? dominantColor = freezed,
    Object? sleepTimerRemaining = freezed,
    Object? lyrics = null,
    Object? lyricsSource = null,
    Object? isLoadingLyrics = null,
    Object? isLyricsVisible = null,
    Object? isQueueVisible = null,
    Object? eqPreset = null,
    Object? isEqEnabled = null,
    Object? isVirtualizerEnabled = null,
    Object? virtualizerStrength = null,
    Object? isDynamicsEnabled = null,
    Object? dynamicsPreset = null,
    Object? selectedHeadphoneProfile = freezed,
    Object? isSpatializerSupported = null,
    Object? isSpatializerEnabled = null,
    Object? volumeBoost = null,
    Object? isCrossfeedEnabled = null,
    Object? crossfeedDelayUs = null,
    Object? crossfeedFeedDb = null,
    Object? isLimiterEnabled = null,
    Object? limiterThresholdDb = null,
    Object? limiterReleaseMs = null,
    Object? isReverbEnabled = null,
    Object? reverbPreset = null,
    Object? reverbWetDry = null,
    Object? stereoBalance = null,
    Object? monoMix = null,
    Object? isSincResamplerEnabled = null,
    Object? hasOemAudio = null,
    Object? detectedOemEngines = null,
    Object? activeQueueSlot = null,
    Object? playbackSpeed = null,
    Object? audioSessionId = freezed,
    Object? errorMessage = freezed,
  }) {
    return _then(_self.copyWith(
      currentSong: freezed == currentSong
          ? _self.currentSong
          : currentSong // ignore: cast_nullable_to_non_nullable
              as SongsTableData?,
      isPlaying: null == isPlaying
          ? _self.isPlaying
          : isPlaying // ignore: cast_nullable_to_non_nullable
              as bool,
      position: null == position
          ? _self.position
          : position // ignore: cast_nullable_to_non_nullable
              as Duration,
      duration: null == duration
          ? _self.duration
          : duration // ignore: cast_nullable_to_non_nullable
              as Duration,
      isShuffle: null == isShuffle
          ? _self.isShuffle
          : isShuffle // ignore: cast_nullable_to_non_nullable
              as bool,
      repeatMode: null == repeatMode
          ? _self.repeatMode
          : repeatMode // ignore: cast_nullable_to_non_nullable
              as PlayerRepeatMode,
      queue: null == queue
          ? _self.queue
          : queue // ignore: cast_nullable_to_non_nullable
              as List<SongsTableData>,
      currentIndex: null == currentIndex
          ? _self.currentIndex
          : currentIndex // ignore: cast_nullable_to_non_nullable
              as int,
      isExpanded: null == isExpanded
          ? _self.isExpanded
          : isExpanded // ignore: cast_nullable_to_non_nullable
              as bool,
      dominantColor: freezed == dominantColor
          ? _self.dominantColor
          : dominantColor // ignore: cast_nullable_to_non_nullable
              as Color?,
      sleepTimerRemaining: freezed == sleepTimerRemaining
          ? _self.sleepTimerRemaining
          : sleepTimerRemaining // ignore: cast_nullable_to_non_nullable
              as Duration?,
      lyrics: null == lyrics
          ? _self.lyrics
          : lyrics // ignore: cast_nullable_to_non_nullable
              as List<LyricsLine>,
      lyricsSource: null == lyricsSource
          ? _self.lyricsSource
          : lyricsSource // ignore: cast_nullable_to_non_nullable
              as LyricsSource,
      isLoadingLyrics: null == isLoadingLyrics
          ? _self.isLoadingLyrics
          : isLoadingLyrics // ignore: cast_nullable_to_non_nullable
              as bool,
      isLyricsVisible: null == isLyricsVisible
          ? _self.isLyricsVisible
          : isLyricsVisible // ignore: cast_nullable_to_non_nullable
              as bool,
      isQueueVisible: null == isQueueVisible
          ? _self.isQueueVisible
          : isQueueVisible // ignore: cast_nullable_to_non_nullable
              as bool,
      eqPreset: null == eqPreset
          ? _self.eqPreset
          : eqPreset // ignore: cast_nullable_to_non_nullable
              as EqPreset,
      isEqEnabled: null == isEqEnabled
          ? _self.isEqEnabled
          : isEqEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      isVirtualizerEnabled: null == isVirtualizerEnabled
          ? _self.isVirtualizerEnabled
          : isVirtualizerEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      virtualizerStrength: null == virtualizerStrength
          ? _self.virtualizerStrength
          : virtualizerStrength // ignore: cast_nullable_to_non_nullable
              as double,
      isDynamicsEnabled: null == isDynamicsEnabled
          ? _self.isDynamicsEnabled
          : isDynamicsEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      dynamicsPreset: null == dynamicsPreset
          ? _self.dynamicsPreset
          : dynamicsPreset // ignore: cast_nullable_to_non_nullable
              as DynamicsPreset,
      selectedHeadphoneProfile: freezed == selectedHeadphoneProfile
          ? _self.selectedHeadphoneProfile
          : selectedHeadphoneProfile // ignore: cast_nullable_to_non_nullable
              as HeadphoneProfile?,
      isSpatializerSupported: null == isSpatializerSupported
          ? _self.isSpatializerSupported
          : isSpatializerSupported // ignore: cast_nullable_to_non_nullable
              as bool,
      isSpatializerEnabled: null == isSpatializerEnabled
          ? _self.isSpatializerEnabled
          : isSpatializerEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      volumeBoost: null == volumeBoost
          ? _self.volumeBoost
          : volumeBoost // ignore: cast_nullable_to_non_nullable
              as double,
      isCrossfeedEnabled: null == isCrossfeedEnabled
          ? _self.isCrossfeedEnabled
          : isCrossfeedEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      crossfeedDelayUs: null == crossfeedDelayUs
          ? _self.crossfeedDelayUs
          : crossfeedDelayUs // ignore: cast_nullable_to_non_nullable
              as double,
      crossfeedFeedDb: null == crossfeedFeedDb
          ? _self.crossfeedFeedDb
          : crossfeedFeedDb // ignore: cast_nullable_to_non_nullable
              as double,
      isLimiterEnabled: null == isLimiterEnabled
          ? _self.isLimiterEnabled
          : isLimiterEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      limiterThresholdDb: null == limiterThresholdDb
          ? _self.limiterThresholdDb
          : limiterThresholdDb // ignore: cast_nullable_to_non_nullable
              as double,
      limiterReleaseMs: null == limiterReleaseMs
          ? _self.limiterReleaseMs
          : limiterReleaseMs // ignore: cast_nullable_to_non_nullable
              as double,
      isReverbEnabled: null == isReverbEnabled
          ? _self.isReverbEnabled
          : isReverbEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      reverbPreset: null == reverbPreset
          ? _self.reverbPreset
          : reverbPreset // ignore: cast_nullable_to_non_nullable
              as int,
      reverbWetDry: null == reverbWetDry
          ? _self.reverbWetDry
          : reverbWetDry // ignore: cast_nullable_to_non_nullable
              as double,
      stereoBalance: null == stereoBalance
          ? _self.stereoBalance
          : stereoBalance // ignore: cast_nullable_to_non_nullable
              as double,
      monoMix: null == monoMix
          ? _self.monoMix
          : monoMix // ignore: cast_nullable_to_non_nullable
              as bool,
      isSincResamplerEnabled: null == isSincResamplerEnabled
          ? _self.isSincResamplerEnabled
          : isSincResamplerEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      hasOemAudio: null == hasOemAudio
          ? _self.hasOemAudio
          : hasOemAudio // ignore: cast_nullable_to_non_nullable
              as bool,
      detectedOemEngines: null == detectedOemEngines
          ? _self.detectedOemEngines
          : detectedOemEngines // ignore: cast_nullable_to_non_nullable
              as List<String>,
      activeQueueSlot: null == activeQueueSlot
          ? _self.activeQueueSlot
          : activeQueueSlot // ignore: cast_nullable_to_non_nullable
              as int,
      playbackSpeed: null == playbackSpeed
          ? _self.playbackSpeed
          : playbackSpeed // ignore: cast_nullable_to_non_nullable
              as double,
      audioSessionId: freezed == audioSessionId
          ? _self.audioSessionId
          : audioSessionId // ignore: cast_nullable_to_non_nullable
              as int?,
      errorMessage: freezed == errorMessage
          ? _self.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// Adds pattern-matching-related methods to [PlayerState].
extension PlayerStatePatterns on PlayerState {
  /// A variant of `map` that fallback to returning `orElse`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>(
    TResult Function(_PlayerState value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _PlayerState() when $default != null:
        return $default(_that);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// Callbacks receives the raw object, upcasted.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case final Subclass2 value:
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult map<TResult extends Object?>(
    TResult Function(_PlayerState value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _PlayerState():
        return $default(_that);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `map` that fallback to returning `null`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>(
    TResult? Function(_PlayerState value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _PlayerState() when $default != null:
        return $default(_that);
      case _:
        return null;
    }
  }

  /// A variant of `when` that fallback to an `orElse` callback.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>(
    TResult Function(
            SongsTableData? currentSong,
            bool isPlaying,
            Duration position,
            Duration duration,
            bool isShuffle,
            PlayerRepeatMode repeatMode,
            List<SongsTableData> queue,
            int currentIndex,
            bool isExpanded,
            Color? dominantColor,
            Duration? sleepTimerRemaining,
            List<LyricsLine> lyrics,
            LyricsSource lyricsSource,
            bool isLoadingLyrics,
            bool isLyricsVisible,
            bool isQueueVisible,
            EqPreset eqPreset,
            bool isEqEnabled,
            bool isVirtualizerEnabled,
            double virtualizerStrength,
            bool isDynamicsEnabled,
            DynamicsPreset dynamicsPreset,
            HeadphoneProfile? selectedHeadphoneProfile,
            bool isSpatializerSupported,
            bool isSpatializerEnabled,
            double volumeBoost,
            bool isCrossfeedEnabled,
            double crossfeedDelayUs,
            double crossfeedFeedDb,
            bool isLimiterEnabled,
            double limiterThresholdDb,
            double limiterReleaseMs,
            bool isReverbEnabled,
            int reverbPreset,
            double reverbWetDry,
            double stereoBalance,
            bool monoMix,
            bool isSincResamplerEnabled,
            bool hasOemAudio,
            List<String> detectedOemEngines,
            int activeQueueSlot,
            double playbackSpeed,
            int? audioSessionId,
            String? errorMessage)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _PlayerState() when $default != null:
        return $default(
            _that.currentSong,
            _that.isPlaying,
            _that.position,
            _that.duration,
            _that.isShuffle,
            _that.repeatMode,
            _that.queue,
            _that.currentIndex,
            _that.isExpanded,
            _that.dominantColor,
            _that.sleepTimerRemaining,
            _that.lyrics,
            _that.lyricsSource,
            _that.isLoadingLyrics,
            _that.isLyricsVisible,
            _that.isQueueVisible,
            _that.eqPreset,
            _that.isEqEnabled,
            _that.isVirtualizerEnabled,
            _that.virtualizerStrength,
            _that.isDynamicsEnabled,
            _that.dynamicsPreset,
            _that.selectedHeadphoneProfile,
            _that.isSpatializerSupported,
            _that.isSpatializerEnabled,
            _that.volumeBoost,
            _that.isCrossfeedEnabled,
            _that.crossfeedDelayUs,
            _that.crossfeedFeedDb,
            _that.isLimiterEnabled,
            _that.limiterThresholdDb,
            _that.limiterReleaseMs,
            _that.isReverbEnabled,
            _that.reverbPreset,
            _that.reverbWetDry,
            _that.stereoBalance,
            _that.monoMix,
            _that.isSincResamplerEnabled,
            _that.hasOemAudio,
            _that.detectedOemEngines,
            _that.activeQueueSlot,
            _that.playbackSpeed,
            _that.audioSessionId,
            _that.errorMessage);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// As opposed to `map`, this offers destructuring.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case Subclass2(:final field2):
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult when<TResult extends Object?>(
    TResult Function(
            SongsTableData? currentSong,
            bool isPlaying,
            Duration position,
            Duration duration,
            bool isShuffle,
            PlayerRepeatMode repeatMode,
            List<SongsTableData> queue,
            int currentIndex,
            bool isExpanded,
            Color? dominantColor,
            Duration? sleepTimerRemaining,
            List<LyricsLine> lyrics,
            LyricsSource lyricsSource,
            bool isLoadingLyrics,
            bool isLyricsVisible,
            bool isQueueVisible,
            EqPreset eqPreset,
            bool isEqEnabled,
            bool isVirtualizerEnabled,
            double virtualizerStrength,
            bool isDynamicsEnabled,
            DynamicsPreset dynamicsPreset,
            HeadphoneProfile? selectedHeadphoneProfile,
            bool isSpatializerSupported,
            bool isSpatializerEnabled,
            double volumeBoost,
            bool isCrossfeedEnabled,
            double crossfeedDelayUs,
            double crossfeedFeedDb,
            bool isLimiterEnabled,
            double limiterThresholdDb,
            double limiterReleaseMs,
            bool isReverbEnabled,
            int reverbPreset,
            double reverbWetDry,
            double stereoBalance,
            bool monoMix,
            bool isSincResamplerEnabled,
            bool hasOemAudio,
            List<String> detectedOemEngines,
            int activeQueueSlot,
            double playbackSpeed,
            int? audioSessionId,
            String? errorMessage)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _PlayerState():
        return $default(
            _that.currentSong,
            _that.isPlaying,
            _that.position,
            _that.duration,
            _that.isShuffle,
            _that.repeatMode,
            _that.queue,
            _that.currentIndex,
            _that.isExpanded,
            _that.dominantColor,
            _that.sleepTimerRemaining,
            _that.lyrics,
            _that.lyricsSource,
            _that.isLoadingLyrics,
            _that.isLyricsVisible,
            _that.isQueueVisible,
            _that.eqPreset,
            _that.isEqEnabled,
            _that.isVirtualizerEnabled,
            _that.virtualizerStrength,
            _that.isDynamicsEnabled,
            _that.dynamicsPreset,
            _that.selectedHeadphoneProfile,
            _that.isSpatializerSupported,
            _that.isSpatializerEnabled,
            _that.volumeBoost,
            _that.isCrossfeedEnabled,
            _that.crossfeedDelayUs,
            _that.crossfeedFeedDb,
            _that.isLimiterEnabled,
            _that.limiterThresholdDb,
            _that.limiterReleaseMs,
            _that.isReverbEnabled,
            _that.reverbPreset,
            _that.reverbWetDry,
            _that.stereoBalance,
            _that.monoMix,
            _that.isSincResamplerEnabled,
            _that.hasOemAudio,
            _that.detectedOemEngines,
            _that.activeQueueSlot,
            _that.playbackSpeed,
            _that.audioSessionId,
            _that.errorMessage);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `when` that fallback to returning `null`
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>(
    TResult? Function(
            SongsTableData? currentSong,
            bool isPlaying,
            Duration position,
            Duration duration,
            bool isShuffle,
            PlayerRepeatMode repeatMode,
            List<SongsTableData> queue,
            int currentIndex,
            bool isExpanded,
            Color? dominantColor,
            Duration? sleepTimerRemaining,
            List<LyricsLine> lyrics,
            LyricsSource lyricsSource,
            bool isLoadingLyrics,
            bool isLyricsVisible,
            bool isQueueVisible,
            EqPreset eqPreset,
            bool isEqEnabled,
            bool isVirtualizerEnabled,
            double virtualizerStrength,
            bool isDynamicsEnabled,
            DynamicsPreset dynamicsPreset,
            HeadphoneProfile? selectedHeadphoneProfile,
            bool isSpatializerSupported,
            bool isSpatializerEnabled,
            double volumeBoost,
            bool isCrossfeedEnabled,
            double crossfeedDelayUs,
            double crossfeedFeedDb,
            bool isLimiterEnabled,
            double limiterThresholdDb,
            double limiterReleaseMs,
            bool isReverbEnabled,
            int reverbPreset,
            double reverbWetDry,
            double stereoBalance,
            bool monoMix,
            bool isSincResamplerEnabled,
            bool hasOemAudio,
            List<String> detectedOemEngines,
            int activeQueueSlot,
            double playbackSpeed,
            int? audioSessionId,
            String? errorMessage)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _PlayerState() when $default != null:
        return $default(
            _that.currentSong,
            _that.isPlaying,
            _that.position,
            _that.duration,
            _that.isShuffle,
            _that.repeatMode,
            _that.queue,
            _that.currentIndex,
            _that.isExpanded,
            _that.dominantColor,
            _that.sleepTimerRemaining,
            _that.lyrics,
            _that.lyricsSource,
            _that.isLoadingLyrics,
            _that.isLyricsVisible,
            _that.isQueueVisible,
            _that.eqPreset,
            _that.isEqEnabled,
            _that.isVirtualizerEnabled,
            _that.virtualizerStrength,
            _that.isDynamicsEnabled,
            _that.dynamicsPreset,
            _that.selectedHeadphoneProfile,
            _that.isSpatializerSupported,
            _that.isSpatializerEnabled,
            _that.volumeBoost,
            _that.isCrossfeedEnabled,
            _that.crossfeedDelayUs,
            _that.crossfeedFeedDb,
            _that.isLimiterEnabled,
            _that.limiterThresholdDb,
            _that.limiterReleaseMs,
            _that.isReverbEnabled,
            _that.reverbPreset,
            _that.reverbWetDry,
            _that.stereoBalance,
            _that.monoMix,
            _that.isSincResamplerEnabled,
            _that.hasOemAudio,
            _that.detectedOemEngines,
            _that.activeQueueSlot,
            _that.playbackSpeed,
            _that.audioSessionId,
            _that.errorMessage);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _PlayerState extends PlayerState {
  const _PlayerState(
      {this.currentSong,
      this.isPlaying = false,
      this.position = Duration.zero,
      this.duration = Duration.zero,
      this.isShuffle = false,
      this.repeatMode = PlayerRepeatMode.off,
      final List<SongsTableData> queue = const [],
      this.currentIndex = 0,
      this.isExpanded = false,
      this.dominantColor,
      this.sleepTimerRemaining,
      final List<LyricsLine> lyrics = const [],
      this.lyricsSource = LyricsSource.none,
      this.isLoadingLyrics = false,
      this.isLyricsVisible = false,
      this.isQueueVisible = false,
      this.eqPreset =
          const EqPreset(name: 'Flat', gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
      this.isEqEnabled = false,
      this.isVirtualizerEnabled = false,
      this.virtualizerStrength = 0.0,
      this.isDynamicsEnabled = false,
      this.dynamicsPreset = DynamicsPreset.off,
      this.selectedHeadphoneProfile,
      this.isSpatializerSupported = false,
      this.isSpatializerEnabled = false,
      this.volumeBoost = 0.0,
      this.isCrossfeedEnabled = false,
      this.crossfeedDelayUs = 350.0,
      this.crossfeedFeedDb = -9.0,
      this.isLimiterEnabled = false,
      this.limiterThresholdDb = -0.2,
      this.limiterReleaseMs = 50.0,
      this.isReverbEnabled = false,
      this.reverbPreset = 0,
      this.reverbWetDry = 0.20,
      this.stereoBalance = 0.0,
      this.monoMix = false,
      this.isSincResamplerEnabled = true,
      this.hasOemAudio = false,
      final List<String> detectedOemEngines = const [],
      this.activeQueueSlot = 0,
      this.playbackSpeed = 1.0,
      this.audioSessionId,
      this.errorMessage})
      : _queue = queue,
        _lyrics = lyrics,
        _detectedOemEngines = detectedOemEngines,
        super._();

  @override
  final SongsTableData? currentSong;
  @override
  @JsonKey()
  final bool isPlaying;
  @override
  @JsonKey()
  final Duration position;
  @override
  @JsonKey()
  final Duration duration;
  @override
  @JsonKey()
  final bool isShuffle;
  @override
  @JsonKey()
  final PlayerRepeatMode repeatMode;
  final List<SongsTableData> _queue;
  @override
  @JsonKey()
  List<SongsTableData> get queue {
    if (_queue is EqualUnmodifiableListView) return _queue;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_queue);
  }

  @override
  @JsonKey()
  final int currentIndex;
  @override
  @JsonKey()
  final bool isExpanded;
  @override
  final Color? dominantColor;
  @override
  final Duration? sleepTimerRemaining;
  final List<LyricsLine> _lyrics;
  @override
  @JsonKey()
  List<LyricsLine> get lyrics {
    if (_lyrics is EqualUnmodifiableListView) return _lyrics;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_lyrics);
  }

  @override
  @JsonKey()
  final LyricsSource lyricsSource;
  @override
  @JsonKey()
  final bool isLoadingLyrics;
  @override
  @JsonKey()
  final bool isLyricsVisible;
  @override
  @JsonKey()
  final bool isQueueVisible;
  @override
  @JsonKey()
  final EqPreset eqPreset;
  @override
  @JsonKey()
  final bool isEqEnabled;
  @override
  @JsonKey()
  final bool isVirtualizerEnabled;
  @override
  @JsonKey()
  final double virtualizerStrength;
  @override
  @JsonKey()
  final bool isDynamicsEnabled;
  @override
  @JsonKey()
  final DynamicsPreset dynamicsPreset;
  @override
  final HeadphoneProfile? selectedHeadphoneProfile;
  @override
  @JsonKey()
  final bool isSpatializerSupported;
  @override
  @JsonKey()
  final bool isSpatializerEnabled;
  @override
  @JsonKey()
  final double volumeBoost;
  @override
  @JsonKey()
  final bool isCrossfeedEnabled;
  @override
  @JsonKey()
  final double crossfeedDelayUs;
  @override
  @JsonKey()
  final double crossfeedFeedDb;
  @override
  @JsonKey()
  final bool isLimiterEnabled;
  @override
  @JsonKey()
  final double limiterThresholdDb;
  @override
  @JsonKey()
  final double limiterReleaseMs;
  @override
  @JsonKey()
  final bool isReverbEnabled;
  @override
  @JsonKey()
  final int reverbPreset;
  @override
  @JsonKey()
  final double reverbWetDry;
  @override
  @JsonKey()
  final double stereoBalance;
  @override
  @JsonKey()
  final bool monoMix;
  @override
  @JsonKey()
  final bool isSincResamplerEnabled;
  @override
  @JsonKey()
  final bool hasOemAudio;
  final List<String> _detectedOemEngines;
  @override
  @JsonKey()
  List<String> get detectedOemEngines {
    if (_detectedOemEngines is EqualUnmodifiableListView)
      return _detectedOemEngines;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_detectedOemEngines);
  }

  @override
  @JsonKey()
  final int activeQueueSlot;
  @override
  @JsonKey()
  final double playbackSpeed;
  @override
  final int? audioSessionId;
  @override
  final String? errorMessage;

  /// Create a copy of PlayerState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$PlayerStateCopyWith<_PlayerState> get copyWith =>
      __$PlayerStateCopyWithImpl<_PlayerState>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _PlayerState &&
            (identical(other.currentSong, currentSong) ||
                other.currentSong == currentSong) &&
            (identical(other.isPlaying, isPlaying) ||
                other.isPlaying == isPlaying) &&
            (identical(other.position, position) ||
                other.position == position) &&
            (identical(other.duration, duration) ||
                other.duration == duration) &&
            (identical(other.isShuffle, isShuffle) ||
                other.isShuffle == isShuffle) &&
            (identical(other.repeatMode, repeatMode) ||
                other.repeatMode == repeatMode) &&
            const DeepCollectionEquality().equals(other._queue, _queue) &&
            (identical(other.currentIndex, currentIndex) ||
                other.currentIndex == currentIndex) &&
            (identical(other.isExpanded, isExpanded) ||
                other.isExpanded == isExpanded) &&
            (identical(other.dominantColor, dominantColor) ||
                other.dominantColor == dominantColor) &&
            (identical(other.sleepTimerRemaining, sleepTimerRemaining) ||
                other.sleepTimerRemaining == sleepTimerRemaining) &&
            const DeepCollectionEquality().equals(other._lyrics, _lyrics) &&
            (identical(other.lyricsSource, lyricsSource) ||
                other.lyricsSource == lyricsSource) &&
            (identical(other.isLoadingLyrics, isLoadingLyrics) ||
                other.isLoadingLyrics == isLoadingLyrics) &&
            (identical(other.isLyricsVisible, isLyricsVisible) ||
                other.isLyricsVisible == isLyricsVisible) &&
            (identical(other.isQueueVisible, isQueueVisible) ||
                other.isQueueVisible == isQueueVisible) &&
            (identical(other.eqPreset, eqPreset) ||
                other.eqPreset == eqPreset) &&
            (identical(other.isEqEnabled, isEqEnabled) ||
                other.isEqEnabled == isEqEnabled) &&
            (identical(other.isVirtualizerEnabled, isVirtualizerEnabled) ||
                other.isVirtualizerEnabled == isVirtualizerEnabled) &&
            (identical(other.virtualizerStrength, virtualizerStrength) ||
                other.virtualizerStrength == virtualizerStrength) &&
            (identical(other.isDynamicsEnabled, isDynamicsEnabled) ||
                other.isDynamicsEnabled == isDynamicsEnabled) &&
            (identical(other.dynamicsPreset, dynamicsPreset) ||
                other.dynamicsPreset == dynamicsPreset) &&
            (identical(other.selectedHeadphoneProfile, selectedHeadphoneProfile) ||
                other.selectedHeadphoneProfile == selectedHeadphoneProfile) &&
            (identical(other.isSpatializerSupported, isSpatializerSupported) ||
                other.isSpatializerSupported == isSpatializerSupported) &&
            (identical(other.isSpatializerEnabled, isSpatializerEnabled) ||
                other.isSpatializerEnabled == isSpatializerEnabled) &&
            (identical(other.volumeBoost, volumeBoost) ||
                other.volumeBoost == volumeBoost) &&
            (identical(other.isCrossfeedEnabled, isCrossfeedEnabled) ||
                other.isCrossfeedEnabled == isCrossfeedEnabled) &&
            (identical(other.crossfeedDelayUs, crossfeedDelayUs) ||
                other.crossfeedDelayUs == crossfeedDelayUs) &&
            (identical(other.crossfeedFeedDb, crossfeedFeedDb) ||
                other.crossfeedFeedDb == crossfeedFeedDb) &&
            (identical(other.isLimiterEnabled, isLimiterEnabled) ||
                other.isLimiterEnabled == isLimiterEnabled) &&
            (identical(other.limiterThresholdDb, limiterThresholdDb) ||
                other.limiterThresholdDb == limiterThresholdDb) &&
            (identical(other.limiterReleaseMs, limiterReleaseMs) ||
                other.limiterReleaseMs == limiterReleaseMs) &&
            (identical(other.isReverbEnabled, isReverbEnabled) ||
                other.isReverbEnabled == isReverbEnabled) &&
            (identical(other.reverbPreset, reverbPreset) ||
                other.reverbPreset == reverbPreset) &&
            (identical(other.reverbWetDry, reverbWetDry) ||
                other.reverbWetDry == reverbWetDry) &&
            (identical(other.stereoBalance, stereoBalance) ||
                other.stereoBalance == stereoBalance) &&
            (identical(other.monoMix, monoMix) || other.monoMix == monoMix) &&
            (identical(other.isSincResamplerEnabled, isSincResamplerEnabled) ||
                other.isSincResamplerEnabled == isSincResamplerEnabled) &&
            (identical(other.hasOemAudio, hasOemAudio) ||
                other.hasOemAudio == hasOemAudio) &&
            const DeepCollectionEquality()
                .equals(other._detectedOemEngines, _detectedOemEngines) &&
            (identical(other.activeQueueSlot, activeQueueSlot) ||
                other.activeQueueSlot == activeQueueSlot) &&
            (identical(other.playbackSpeed, playbackSpeed) ||
                other.playbackSpeed == playbackSpeed) &&
            (identical(other.audioSessionId, audioSessionId) || other.audioSessionId == audioSessionId) &&
            (identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
  }

  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        currentSong,
        isPlaying,
        position,
        duration,
        isShuffle,
        repeatMode,
        const DeepCollectionEquality().hash(_queue),
        currentIndex,
        isExpanded,
        dominantColor,
        sleepTimerRemaining,
        const DeepCollectionEquality().hash(_lyrics),
        lyricsSource,
        isLoadingLyrics,
        isLyricsVisible,
        isQueueVisible,
        eqPreset,
        isEqEnabled,
        isVirtualizerEnabled,
        virtualizerStrength,
        isDynamicsEnabled,
        dynamicsPreset,
        selectedHeadphoneProfile,
        isSpatializerSupported,
        isSpatializerEnabled,
        volumeBoost,
        isCrossfeedEnabled,
        crossfeedDelayUs,
        crossfeedFeedDb,
        isLimiterEnabled,
        limiterThresholdDb,
        limiterReleaseMs,
        isReverbEnabled,
        reverbPreset,
        reverbWetDry,
        stereoBalance,
        monoMix,
        isSincResamplerEnabled,
        hasOemAudio,
        const DeepCollectionEquality().hash(_detectedOemEngines),
        activeQueueSlot,
        playbackSpeed,
        audioSessionId,
        errorMessage
      ]);

  @override
  String toString() {
    return 'PlayerState(currentSong: $currentSong, isPlaying: $isPlaying, position: $position, duration: $duration, isShuffle: $isShuffle, repeatMode: $repeatMode, queue: $queue, currentIndex: $currentIndex, isExpanded: $isExpanded, dominantColor: $dominantColor, sleepTimerRemaining: $sleepTimerRemaining, lyrics: $lyrics, lyricsSource: $lyricsSource, isLoadingLyrics: $isLoadingLyrics, isLyricsVisible: $isLyricsVisible, isQueueVisible: $isQueueVisible, eqPreset: $eqPreset, isEqEnabled: $isEqEnabled, isVirtualizerEnabled: $isVirtualizerEnabled, virtualizerStrength: $virtualizerStrength, isDynamicsEnabled: $isDynamicsEnabled, dynamicsPreset: $dynamicsPreset, selectedHeadphoneProfile: $selectedHeadphoneProfile, isSpatializerSupported: $isSpatializerSupported, isSpatializerEnabled: $isSpatializerEnabled, volumeBoost: $volumeBoost, isCrossfeedEnabled: $isCrossfeedEnabled, crossfeedDelayUs: $crossfeedDelayUs, crossfeedFeedDb: $crossfeedFeedDb, isLimiterEnabled: $isLimiterEnabled, limiterThresholdDb: $limiterThresholdDb, limiterReleaseMs: $limiterReleaseMs, isReverbEnabled: $isReverbEnabled, reverbPreset: $reverbPreset, reverbWetDry: $reverbWetDry, stereoBalance: $stereoBalance, monoMix: $monoMix, isSincResamplerEnabled: $isSincResamplerEnabled, hasOemAudio: $hasOemAudio, detectedOemEngines: $detectedOemEngines, activeQueueSlot: $activeQueueSlot, playbackSpeed: $playbackSpeed, audioSessionId: $audioSessionId, errorMessage: $errorMessage)';
  }
}

/// @nodoc
abstract mixin class _$PlayerStateCopyWith<$Res>
    implements $PlayerStateCopyWith<$Res> {
  factory _$PlayerStateCopyWith(
          _PlayerState value, $Res Function(_PlayerState) _then) =
      __$PlayerStateCopyWithImpl;
  @override
  @useResult
  $Res call(
      {SongsTableData? currentSong,
      bool isPlaying,
      Duration position,
      Duration duration,
      bool isShuffle,
      PlayerRepeatMode repeatMode,
      List<SongsTableData> queue,
      int currentIndex,
      bool isExpanded,
      Color? dominantColor,
      Duration? sleepTimerRemaining,
      List<LyricsLine> lyrics,
      LyricsSource lyricsSource,
      bool isLoadingLyrics,
      bool isLyricsVisible,
      bool isQueueVisible,
      EqPreset eqPreset,
      bool isEqEnabled,
      bool isVirtualizerEnabled,
      double virtualizerStrength,
      bool isDynamicsEnabled,
      DynamicsPreset dynamicsPreset,
      HeadphoneProfile? selectedHeadphoneProfile,
      bool isSpatializerSupported,
      bool isSpatializerEnabled,
      double volumeBoost,
      bool isCrossfeedEnabled,
      double crossfeedDelayUs,
      double crossfeedFeedDb,
      bool isLimiterEnabled,
      double limiterThresholdDb,
      double limiterReleaseMs,
      bool isReverbEnabled,
      int reverbPreset,
      double reverbWetDry,
      double stereoBalance,
      bool monoMix,
      bool isSincResamplerEnabled,
      bool hasOemAudio,
      List<String> detectedOemEngines,
      int activeQueueSlot,
      double playbackSpeed,
      int? audioSessionId,
      String? errorMessage});
}

/// @nodoc
class __$PlayerStateCopyWithImpl<$Res> implements _$PlayerStateCopyWith<$Res> {
  __$PlayerStateCopyWithImpl(this._self, this._then);

  final _PlayerState _self;
  final $Res Function(_PlayerState) _then;

  /// Create a copy of PlayerState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? currentSong = freezed,
    Object? isPlaying = null,
    Object? position = null,
    Object? duration = null,
    Object? isShuffle = null,
    Object? repeatMode = null,
    Object? queue = null,
    Object? currentIndex = null,
    Object? isExpanded = null,
    Object? dominantColor = freezed,
    Object? sleepTimerRemaining = freezed,
    Object? lyrics = null,
    Object? lyricsSource = null,
    Object? isLoadingLyrics = null,
    Object? isLyricsVisible = null,
    Object? isQueueVisible = null,
    Object? eqPreset = null,
    Object? isEqEnabled = null,
    Object? isVirtualizerEnabled = null,
    Object? virtualizerStrength = null,
    Object? isDynamicsEnabled = null,
    Object? dynamicsPreset = null,
    Object? selectedHeadphoneProfile = freezed,
    Object? isSpatializerSupported = null,
    Object? isSpatializerEnabled = null,
    Object? volumeBoost = null,
    Object? isCrossfeedEnabled = null,
    Object? crossfeedDelayUs = null,
    Object? crossfeedFeedDb = null,
    Object? isLimiterEnabled = null,
    Object? limiterThresholdDb = null,
    Object? limiterReleaseMs = null,
    Object? isReverbEnabled = null,
    Object? reverbPreset = null,
    Object? reverbWetDry = null,
    Object? stereoBalance = null,
    Object? monoMix = null,
    Object? isSincResamplerEnabled = null,
    Object? hasOemAudio = null,
    Object? detectedOemEngines = null,
    Object? activeQueueSlot = null,
    Object? playbackSpeed = null,
    Object? audioSessionId = freezed,
    Object? errorMessage = freezed,
  }) {
    return _then(_PlayerState(
      currentSong: freezed == currentSong
          ? _self.currentSong
          : currentSong // ignore: cast_nullable_to_non_nullable
              as SongsTableData?,
      isPlaying: null == isPlaying
          ? _self.isPlaying
          : isPlaying // ignore: cast_nullable_to_non_nullable
              as bool,
      position: null == position
          ? _self.position
          : position // ignore: cast_nullable_to_non_nullable
              as Duration,
      duration: null == duration
          ? _self.duration
          : duration // ignore: cast_nullable_to_non_nullable
              as Duration,
      isShuffle: null == isShuffle
          ? _self.isShuffle
          : isShuffle // ignore: cast_nullable_to_non_nullable
              as bool,
      repeatMode: null == repeatMode
          ? _self.repeatMode
          : repeatMode // ignore: cast_nullable_to_non_nullable
              as PlayerRepeatMode,
      queue: null == queue
          ? _self._queue
          : queue // ignore: cast_nullable_to_non_nullable
              as List<SongsTableData>,
      currentIndex: null == currentIndex
          ? _self.currentIndex
          : currentIndex // ignore: cast_nullable_to_non_nullable
              as int,
      isExpanded: null == isExpanded
          ? _self.isExpanded
          : isExpanded // ignore: cast_nullable_to_non_nullable
              as bool,
      dominantColor: freezed == dominantColor
          ? _self.dominantColor
          : dominantColor // ignore: cast_nullable_to_non_nullable
              as Color?,
      sleepTimerRemaining: freezed == sleepTimerRemaining
          ? _self.sleepTimerRemaining
          : sleepTimerRemaining // ignore: cast_nullable_to_non_nullable
              as Duration?,
      lyrics: null == lyrics
          ? _self._lyrics
          : lyrics // ignore: cast_nullable_to_non_nullable
              as List<LyricsLine>,
      lyricsSource: null == lyricsSource
          ? _self.lyricsSource
          : lyricsSource // ignore: cast_nullable_to_non_nullable
              as LyricsSource,
      isLoadingLyrics: null == isLoadingLyrics
          ? _self.isLoadingLyrics
          : isLoadingLyrics // ignore: cast_nullable_to_non_nullable
              as bool,
      isLyricsVisible: null == isLyricsVisible
          ? _self.isLyricsVisible
          : isLyricsVisible // ignore: cast_nullable_to_non_nullable
              as bool,
      isQueueVisible: null == isQueueVisible
          ? _self.isQueueVisible
          : isQueueVisible // ignore: cast_nullable_to_non_nullable
              as bool,
      eqPreset: null == eqPreset
          ? _self.eqPreset
          : eqPreset // ignore: cast_nullable_to_non_nullable
              as EqPreset,
      isEqEnabled: null == isEqEnabled
          ? _self.isEqEnabled
          : isEqEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      isVirtualizerEnabled: null == isVirtualizerEnabled
          ? _self.isVirtualizerEnabled
          : isVirtualizerEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      virtualizerStrength: null == virtualizerStrength
          ? _self.virtualizerStrength
          : virtualizerStrength // ignore: cast_nullable_to_non_nullable
              as double,
      isDynamicsEnabled: null == isDynamicsEnabled
          ? _self.isDynamicsEnabled
          : isDynamicsEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      dynamicsPreset: null == dynamicsPreset
          ? _self.dynamicsPreset
          : dynamicsPreset // ignore: cast_nullable_to_non_nullable
              as DynamicsPreset,
      selectedHeadphoneProfile: freezed == selectedHeadphoneProfile
          ? _self.selectedHeadphoneProfile
          : selectedHeadphoneProfile // ignore: cast_nullable_to_non_nullable
              as HeadphoneProfile?,
      isSpatializerSupported: null == isSpatializerSupported
          ? _self.isSpatializerSupported
          : isSpatializerSupported // ignore: cast_nullable_to_non_nullable
              as bool,
      isSpatializerEnabled: null == isSpatializerEnabled
          ? _self.isSpatializerEnabled
          : isSpatializerEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      volumeBoost: null == volumeBoost
          ? _self.volumeBoost
          : volumeBoost // ignore: cast_nullable_to_non_nullable
              as double,
      isCrossfeedEnabled: null == isCrossfeedEnabled
          ? _self.isCrossfeedEnabled
          : isCrossfeedEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      crossfeedDelayUs: null == crossfeedDelayUs
          ? _self.crossfeedDelayUs
          : crossfeedDelayUs // ignore: cast_nullable_to_non_nullable
              as double,
      crossfeedFeedDb: null == crossfeedFeedDb
          ? _self.crossfeedFeedDb
          : crossfeedFeedDb // ignore: cast_nullable_to_non_nullable
              as double,
      isLimiterEnabled: null == isLimiterEnabled
          ? _self.isLimiterEnabled
          : isLimiterEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      limiterThresholdDb: null == limiterThresholdDb
          ? _self.limiterThresholdDb
          : limiterThresholdDb // ignore: cast_nullable_to_non_nullable
              as double,
      limiterReleaseMs: null == limiterReleaseMs
          ? _self.limiterReleaseMs
          : limiterReleaseMs // ignore: cast_nullable_to_non_nullable
              as double,
      isReverbEnabled: null == isReverbEnabled
          ? _self.isReverbEnabled
          : isReverbEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      reverbPreset: null == reverbPreset
          ? _self.reverbPreset
          : reverbPreset // ignore: cast_nullable_to_non_nullable
              as int,
      reverbWetDry: null == reverbWetDry
          ? _self.reverbWetDry
          : reverbWetDry // ignore: cast_nullable_to_non_nullable
              as double,
      stereoBalance: null == stereoBalance
          ? _self.stereoBalance
          : stereoBalance // ignore: cast_nullable_to_non_nullable
              as double,
      monoMix: null == monoMix
          ? _self.monoMix
          : monoMix // ignore: cast_nullable_to_non_nullable
              as bool,
      isSincResamplerEnabled: null == isSincResamplerEnabled
          ? _self.isSincResamplerEnabled
          : isSincResamplerEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      hasOemAudio: null == hasOemAudio
          ? _self.hasOemAudio
          : hasOemAudio // ignore: cast_nullable_to_non_nullable
              as bool,
      detectedOemEngines: null == detectedOemEngines
          ? _self._detectedOemEngines
          : detectedOemEngines // ignore: cast_nullable_to_non_nullable
              as List<String>,
      activeQueueSlot: null == activeQueueSlot
          ? _self.activeQueueSlot
          : activeQueueSlot // ignore: cast_nullable_to_non_nullable
              as int,
      playbackSpeed: null == playbackSpeed
          ? _self.playbackSpeed
          : playbackSpeed // ignore: cast_nullable_to_non_nullable
              as double,
      audioSessionId: freezed == audioSessionId
          ? _self.audioSessionId
          : audioSessionId // ignore: cast_nullable_to_non_nullable
              as int?,
      errorMessage: freezed == errorMessage
          ? _self.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

// dart format on
