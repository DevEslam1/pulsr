// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'settings_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SettingsState {
  bool get gaplessPlayback;
  double get crossfadeSeconds;
  int get minDurationSec;
  bool get dynamicThemingEnabled;
  bool get resumeAfterInterruption;
  bool get waveformSeekBarEnabled;
  AppThemeMode get themeMode;
  int get customAccentColorValue;
  PlayerThemeMode get playerThemeMode;
  VisualizerStyle get visualizerStyle;
  MiniPlayerSwipeAction get miniPlayerSwipeLeft;
  MiniPlayerSwipeAction get miniPlayerSwipeRight;
  NowPlayingDoubleTapAction get nowPlayingDoubleTap;
  NowPlayingArtworkSwipeAction get nowPlayingArtworkSwipe;
  bool get isScanning;
  int? get scanResultCount;
  String? get errorMessage;

  /// Create a copy of SettingsState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $SettingsStateCopyWith<SettingsState> get copyWith =>
      _$SettingsStateCopyWithImpl<SettingsState>(
          this as SettingsState, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is SettingsState &&
            (identical(other.gaplessPlayback, gaplessPlayback) ||
                other.gaplessPlayback == gaplessPlayback) &&
            (identical(other.crossfadeSeconds, crossfadeSeconds) ||
                other.crossfadeSeconds == crossfadeSeconds) &&
            (identical(other.minDurationSec, minDurationSec) ||
                other.minDurationSec == minDurationSec) &&
            (identical(other.dynamicThemingEnabled, dynamicThemingEnabled) ||
                other.dynamicThemingEnabled == dynamicThemingEnabled) &&
            (identical(
                    other.resumeAfterInterruption, resumeAfterInterruption) ||
                other.resumeAfterInterruption == resumeAfterInterruption) &&
            (identical(other.waveformSeekBarEnabled, waveformSeekBarEnabled) ||
                other.waveformSeekBarEnabled == waveformSeekBarEnabled) &&
            (identical(other.themeMode, themeMode) ||
                other.themeMode == themeMode) &&
            (identical(other.customAccentColorValue, customAccentColorValue) ||
                other.customAccentColorValue == customAccentColorValue) &&
            (identical(other.playerThemeMode, playerThemeMode) ||
                other.playerThemeMode == playerThemeMode) &&
            (identical(other.visualizerStyle, visualizerStyle) ||
                other.visualizerStyle == visualizerStyle) &&
            (identical(other.miniPlayerSwipeLeft, miniPlayerSwipeLeft) ||
                other.miniPlayerSwipeLeft == miniPlayerSwipeLeft) &&
            (identical(other.miniPlayerSwipeRight, miniPlayerSwipeRight) ||
                other.miniPlayerSwipeRight == miniPlayerSwipeRight) &&
            (identical(other.nowPlayingDoubleTap, nowPlayingDoubleTap) ||
                other.nowPlayingDoubleTap == nowPlayingDoubleTap) &&
            (identical(other.nowPlayingArtworkSwipe, nowPlayingArtworkSwipe) ||
                other.nowPlayingArtworkSwipe == nowPlayingArtworkSwipe) &&
            (identical(other.isScanning, isScanning) ||
                other.isScanning == isScanning) &&
            (identical(other.scanResultCount, scanResultCount) ||
                other.scanResultCount == scanResultCount) &&
            (identical(other.errorMessage, errorMessage) ||
                other.errorMessage == errorMessage));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      gaplessPlayback,
      crossfadeSeconds,
      minDurationSec,
      dynamicThemingEnabled,
      resumeAfterInterruption,
      waveformSeekBarEnabled,
      themeMode,
      customAccentColorValue,
      playerThemeMode,
      visualizerStyle,
      miniPlayerSwipeLeft,
      miniPlayerSwipeRight,
      nowPlayingDoubleTap,
      nowPlayingArtworkSwipe,
      isScanning,
      scanResultCount,
      errorMessage);

  @override
  String toString() {
    return 'SettingsState(gaplessPlayback: $gaplessPlayback, crossfadeSeconds: $crossfadeSeconds, minDurationSec: $minDurationSec, dynamicThemingEnabled: $dynamicThemingEnabled, resumeAfterInterruption: $resumeAfterInterruption, waveformSeekBarEnabled: $waveformSeekBarEnabled, themeMode: $themeMode, customAccentColorValue: $customAccentColorValue, playerThemeMode: $playerThemeMode, visualizerStyle: $visualizerStyle, miniPlayerSwipeLeft: $miniPlayerSwipeLeft, miniPlayerSwipeRight: $miniPlayerSwipeRight, nowPlayingDoubleTap: $nowPlayingDoubleTap, nowPlayingArtworkSwipe: $nowPlayingArtworkSwipe, isScanning: $isScanning, scanResultCount: $scanResultCount, errorMessage: $errorMessage)';
  }
}

/// @nodoc
abstract mixin class $SettingsStateCopyWith<$Res> {
  factory $SettingsStateCopyWith(
          SettingsState value, $Res Function(SettingsState) _then) =
      _$SettingsStateCopyWithImpl;
  @useResult
  $Res call(
      {bool gaplessPlayback,
      double crossfadeSeconds,
      int minDurationSec,
      bool dynamicThemingEnabled,
      bool resumeAfterInterruption,
      bool waveformSeekBarEnabled,
      AppThemeMode themeMode,
      int customAccentColorValue,
      PlayerThemeMode playerThemeMode,
      VisualizerStyle visualizerStyle,
      MiniPlayerSwipeAction miniPlayerSwipeLeft,
      MiniPlayerSwipeAction miniPlayerSwipeRight,
      NowPlayingDoubleTapAction nowPlayingDoubleTap,
      NowPlayingArtworkSwipeAction nowPlayingArtworkSwipe,
      bool isScanning,
      int? scanResultCount,
      String? errorMessage});
}

/// @nodoc
class _$SettingsStateCopyWithImpl<$Res>
    implements $SettingsStateCopyWith<$Res> {
  _$SettingsStateCopyWithImpl(this._self, this._then);

  final SettingsState _self;
  final $Res Function(SettingsState) _then;

  /// Create a copy of SettingsState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? gaplessPlayback = null,
    Object? crossfadeSeconds = null,
    Object? minDurationSec = null,
    Object? dynamicThemingEnabled = null,
    Object? resumeAfterInterruption = null,
    Object? waveformSeekBarEnabled = null,
    Object? themeMode = null,
    Object? customAccentColorValue = null,
    Object? playerThemeMode = null,
    Object? visualizerStyle = null,
    Object? miniPlayerSwipeLeft = null,
    Object? miniPlayerSwipeRight = null,
    Object? nowPlayingDoubleTap = null,
    Object? nowPlayingArtworkSwipe = null,
    Object? isScanning = null,
    Object? scanResultCount = freezed,
    Object? errorMessage = freezed,
  }) {
    return _then(_self.copyWith(
      gaplessPlayback: null == gaplessPlayback
          ? _self.gaplessPlayback
          : gaplessPlayback // ignore: cast_nullable_to_non_nullable
              as bool,
      crossfadeSeconds: null == crossfadeSeconds
          ? _self.crossfadeSeconds
          : crossfadeSeconds // ignore: cast_nullable_to_non_nullable
              as double,
      minDurationSec: null == minDurationSec
          ? _self.minDurationSec
          : minDurationSec // ignore: cast_nullable_to_non_nullable
              as int,
      dynamicThemingEnabled: null == dynamicThemingEnabled
          ? _self.dynamicThemingEnabled
          : dynamicThemingEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      resumeAfterInterruption: null == resumeAfterInterruption
          ? _self.resumeAfterInterruption
          : resumeAfterInterruption // ignore: cast_nullable_to_non_nullable
              as bool,
      waveformSeekBarEnabled: null == waveformSeekBarEnabled
          ? _self.waveformSeekBarEnabled
          : waveformSeekBarEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      themeMode: null == themeMode
          ? _self.themeMode
          : themeMode // ignore: cast_nullable_to_non_nullable
              as AppThemeMode,
      customAccentColorValue: null == customAccentColorValue
          ? _self.customAccentColorValue
          : customAccentColorValue // ignore: cast_nullable_to_non_nullable
              as int,
      playerThemeMode: null == playerThemeMode
          ? _self.playerThemeMode
          : playerThemeMode // ignore: cast_nullable_to_non_nullable
              as PlayerThemeMode,
      visualizerStyle: null == visualizerStyle
          ? _self.visualizerStyle
          : visualizerStyle // ignore: cast_nullable_to_non_nullable
              as VisualizerStyle,
      miniPlayerSwipeLeft: null == miniPlayerSwipeLeft
          ? _self.miniPlayerSwipeLeft
          : miniPlayerSwipeLeft // ignore: cast_nullable_to_non_nullable
              as MiniPlayerSwipeAction,
      miniPlayerSwipeRight: null == miniPlayerSwipeRight
          ? _self.miniPlayerSwipeRight
          : miniPlayerSwipeRight // ignore: cast_nullable_to_non_nullable
              as MiniPlayerSwipeAction,
      nowPlayingDoubleTap: null == nowPlayingDoubleTap
          ? _self.nowPlayingDoubleTap
          : nowPlayingDoubleTap // ignore: cast_nullable_to_non_nullable
              as NowPlayingDoubleTapAction,
      nowPlayingArtworkSwipe: null == nowPlayingArtworkSwipe
          ? _self.nowPlayingArtworkSwipe
          : nowPlayingArtworkSwipe // ignore: cast_nullable_to_non_nullable
              as NowPlayingArtworkSwipeAction,
      isScanning: null == isScanning
          ? _self.isScanning
          : isScanning // ignore: cast_nullable_to_non_nullable
              as bool,
      scanResultCount: freezed == scanResultCount
          ? _self.scanResultCount
          : scanResultCount // ignore: cast_nullable_to_non_nullable
              as int?,
      errorMessage: freezed == errorMessage
          ? _self.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// Adds pattern-matching-related methods to [SettingsState].
extension SettingsStatePatterns on SettingsState {
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
    TResult Function(_SettingsState value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _SettingsState() when $default != null:
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
    TResult Function(_SettingsState value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SettingsState():
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
    TResult? Function(_SettingsState value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SettingsState() when $default != null:
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
            bool gaplessPlayback,
            double crossfadeSeconds,
            int minDurationSec,
            bool dynamicThemingEnabled,
            bool resumeAfterInterruption,
            bool waveformSeekBarEnabled,
            AppThemeMode themeMode,
            int customAccentColorValue,
            PlayerThemeMode playerThemeMode,
            VisualizerStyle visualizerStyle,
            MiniPlayerSwipeAction miniPlayerSwipeLeft,
            MiniPlayerSwipeAction miniPlayerSwipeRight,
            NowPlayingDoubleTapAction nowPlayingDoubleTap,
            NowPlayingArtworkSwipeAction nowPlayingArtworkSwipe,
            bool isScanning,
            int? scanResultCount,
            String? errorMessage)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _SettingsState() when $default != null:
        return $default(
            _that.gaplessPlayback,
            _that.crossfadeSeconds,
            _that.minDurationSec,
            _that.dynamicThemingEnabled,
            _that.resumeAfterInterruption,
            _that.waveformSeekBarEnabled,
            _that.themeMode,
            _that.customAccentColorValue,
            _that.playerThemeMode,
            _that.visualizerStyle,
            _that.miniPlayerSwipeLeft,
            _that.miniPlayerSwipeRight,
            _that.nowPlayingDoubleTap,
            _that.nowPlayingArtworkSwipe,
            _that.isScanning,
            _that.scanResultCount,
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
            bool gaplessPlayback,
            double crossfadeSeconds,
            int minDurationSec,
            bool dynamicThemingEnabled,
            bool resumeAfterInterruption,
            bool waveformSeekBarEnabled,
            AppThemeMode themeMode,
            int customAccentColorValue,
            PlayerThemeMode playerThemeMode,
            VisualizerStyle visualizerStyle,
            MiniPlayerSwipeAction miniPlayerSwipeLeft,
            MiniPlayerSwipeAction miniPlayerSwipeRight,
            NowPlayingDoubleTapAction nowPlayingDoubleTap,
            NowPlayingArtworkSwipeAction nowPlayingArtworkSwipe,
            bool isScanning,
            int? scanResultCount,
            String? errorMessage)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SettingsState():
        return $default(
            _that.gaplessPlayback,
            _that.crossfadeSeconds,
            _that.minDurationSec,
            _that.dynamicThemingEnabled,
            _that.resumeAfterInterruption,
            _that.waveformSeekBarEnabled,
            _that.themeMode,
            _that.customAccentColorValue,
            _that.playerThemeMode,
            _that.visualizerStyle,
            _that.miniPlayerSwipeLeft,
            _that.miniPlayerSwipeRight,
            _that.nowPlayingDoubleTap,
            _that.nowPlayingArtworkSwipe,
            _that.isScanning,
            _that.scanResultCount,
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
            bool gaplessPlayback,
            double crossfadeSeconds,
            int minDurationSec,
            bool dynamicThemingEnabled,
            bool resumeAfterInterruption,
            bool waveformSeekBarEnabled,
            AppThemeMode themeMode,
            int customAccentColorValue,
            PlayerThemeMode playerThemeMode,
            VisualizerStyle visualizerStyle,
            MiniPlayerSwipeAction miniPlayerSwipeLeft,
            MiniPlayerSwipeAction miniPlayerSwipeRight,
            NowPlayingDoubleTapAction nowPlayingDoubleTap,
            NowPlayingArtworkSwipeAction nowPlayingArtworkSwipe,
            bool isScanning,
            int? scanResultCount,
            String? errorMessage)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SettingsState() when $default != null:
        return $default(
            _that.gaplessPlayback,
            _that.crossfadeSeconds,
            _that.minDurationSec,
            _that.dynamicThemingEnabled,
            _that.resumeAfterInterruption,
            _that.waveformSeekBarEnabled,
            _that.themeMode,
            _that.customAccentColorValue,
            _that.playerThemeMode,
            _that.visualizerStyle,
            _that.miniPlayerSwipeLeft,
            _that.miniPlayerSwipeRight,
            _that.nowPlayingDoubleTap,
            _that.nowPlayingArtworkSwipe,
            _that.isScanning,
            _that.scanResultCount,
            _that.errorMessage);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _SettingsState extends SettingsState {
  const _SettingsState(
      {this.gaplessPlayback = true,
      this.crossfadeSeconds = 0.0,
      this.minDurationSec = 30,
      this.dynamicThemingEnabled = true,
      this.resumeAfterInterruption = true,
      this.waveformSeekBarEnabled = true,
      this.themeMode = AppThemeMode.dark,
      this.customAccentColorValue = 0xFF9B9EF5,
      this.playerThemeMode = PlayerThemeMode.classic,
      this.visualizerStyle = VisualizerStyle.bar,
      this.miniPlayerSwipeLeft = MiniPlayerSwipeAction.next,
      this.miniPlayerSwipeRight = MiniPlayerSwipeAction.prev,
      this.nowPlayingDoubleTap = NowPlayingDoubleTapAction.toggleFavorite,
      this.nowPlayingArtworkSwipe = NowPlayingArtworkSwipeAction.nextPrev,
      this.isScanning = false,
      this.scanResultCount,
      this.errorMessage})
      : super._();

  @override
  @JsonKey()
  final bool gaplessPlayback;
  @override
  @JsonKey()
  final double crossfadeSeconds;
  @override
  @JsonKey()
  final int minDurationSec;
  @override
  @JsonKey()
  final bool dynamicThemingEnabled;
  @override
  @JsonKey()
  final bool resumeAfterInterruption;
  @override
  @JsonKey()
  final bool waveformSeekBarEnabled;
  @override
  @JsonKey()
  final AppThemeMode themeMode;
  @override
  @JsonKey()
  final int customAccentColorValue;
  @override
  @JsonKey()
  final PlayerThemeMode playerThemeMode;
  @override
  @JsonKey()
  final VisualizerStyle visualizerStyle;
  @override
  @JsonKey()
  final MiniPlayerSwipeAction miniPlayerSwipeLeft;
  @override
  @JsonKey()
  final MiniPlayerSwipeAction miniPlayerSwipeRight;
  @override
  @JsonKey()
  final NowPlayingDoubleTapAction nowPlayingDoubleTap;
  @override
  @JsonKey()
  final NowPlayingArtworkSwipeAction nowPlayingArtworkSwipe;
  @override
  @JsonKey()
  final bool isScanning;
  @override
  final int? scanResultCount;
  @override
  final String? errorMessage;

  /// Create a copy of SettingsState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$SettingsStateCopyWith<_SettingsState> get copyWith =>
      __$SettingsStateCopyWithImpl<_SettingsState>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _SettingsState &&
            (identical(other.gaplessPlayback, gaplessPlayback) ||
                other.gaplessPlayback == gaplessPlayback) &&
            (identical(other.crossfadeSeconds, crossfadeSeconds) ||
                other.crossfadeSeconds == crossfadeSeconds) &&
            (identical(other.minDurationSec, minDurationSec) ||
                other.minDurationSec == minDurationSec) &&
            (identical(other.dynamicThemingEnabled, dynamicThemingEnabled) ||
                other.dynamicThemingEnabled == dynamicThemingEnabled) &&
            (identical(
                    other.resumeAfterInterruption, resumeAfterInterruption) ||
                other.resumeAfterInterruption == resumeAfterInterruption) &&
            (identical(other.waveformSeekBarEnabled, waveformSeekBarEnabled) ||
                other.waveformSeekBarEnabled == waveformSeekBarEnabled) &&
            (identical(other.themeMode, themeMode) ||
                other.themeMode == themeMode) &&
            (identical(other.customAccentColorValue, customAccentColorValue) ||
                other.customAccentColorValue == customAccentColorValue) &&
            (identical(other.playerThemeMode, playerThemeMode) ||
                other.playerThemeMode == playerThemeMode) &&
            (identical(other.visualizerStyle, visualizerStyle) ||
                other.visualizerStyle == visualizerStyle) &&
            (identical(other.miniPlayerSwipeLeft, miniPlayerSwipeLeft) ||
                other.miniPlayerSwipeLeft == miniPlayerSwipeLeft) &&
            (identical(other.miniPlayerSwipeRight, miniPlayerSwipeRight) ||
                other.miniPlayerSwipeRight == miniPlayerSwipeRight) &&
            (identical(other.nowPlayingDoubleTap, nowPlayingDoubleTap) ||
                other.nowPlayingDoubleTap == nowPlayingDoubleTap) &&
            (identical(other.nowPlayingArtworkSwipe, nowPlayingArtworkSwipe) ||
                other.nowPlayingArtworkSwipe == nowPlayingArtworkSwipe) &&
            (identical(other.isScanning, isScanning) ||
                other.isScanning == isScanning) &&
            (identical(other.scanResultCount, scanResultCount) ||
                other.scanResultCount == scanResultCount) &&
            (identical(other.errorMessage, errorMessage) ||
                other.errorMessage == errorMessage));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      gaplessPlayback,
      crossfadeSeconds,
      minDurationSec,
      dynamicThemingEnabled,
      resumeAfterInterruption,
      waveformSeekBarEnabled,
      themeMode,
      customAccentColorValue,
      playerThemeMode,
      visualizerStyle,
      miniPlayerSwipeLeft,
      miniPlayerSwipeRight,
      nowPlayingDoubleTap,
      nowPlayingArtworkSwipe,
      isScanning,
      scanResultCount,
      errorMessage);

  @override
  String toString() {
    return 'SettingsState(gaplessPlayback: $gaplessPlayback, crossfadeSeconds: $crossfadeSeconds, minDurationSec: $minDurationSec, dynamicThemingEnabled: $dynamicThemingEnabled, resumeAfterInterruption: $resumeAfterInterruption, waveformSeekBarEnabled: $waveformSeekBarEnabled, themeMode: $themeMode, customAccentColorValue: $customAccentColorValue, playerThemeMode: $playerThemeMode, visualizerStyle: $visualizerStyle, miniPlayerSwipeLeft: $miniPlayerSwipeLeft, miniPlayerSwipeRight: $miniPlayerSwipeRight, nowPlayingDoubleTap: $nowPlayingDoubleTap, nowPlayingArtworkSwipe: $nowPlayingArtworkSwipe, isScanning: $isScanning, scanResultCount: $scanResultCount, errorMessage: $errorMessage)';
  }
}

/// @nodoc
abstract mixin class _$SettingsStateCopyWith<$Res>
    implements $SettingsStateCopyWith<$Res> {
  factory _$SettingsStateCopyWith(
          _SettingsState value, $Res Function(_SettingsState) _then) =
      __$SettingsStateCopyWithImpl;
  @override
  @useResult
  $Res call(
      {bool gaplessPlayback,
      double crossfadeSeconds,
      int minDurationSec,
      bool dynamicThemingEnabled,
      bool resumeAfterInterruption,
      bool waveformSeekBarEnabled,
      AppThemeMode themeMode,
      int customAccentColorValue,
      PlayerThemeMode playerThemeMode,
      VisualizerStyle visualizerStyle,
      MiniPlayerSwipeAction miniPlayerSwipeLeft,
      MiniPlayerSwipeAction miniPlayerSwipeRight,
      NowPlayingDoubleTapAction nowPlayingDoubleTap,
      NowPlayingArtworkSwipeAction nowPlayingArtworkSwipe,
      bool isScanning,
      int? scanResultCount,
      String? errorMessage});
}

/// @nodoc
class __$SettingsStateCopyWithImpl<$Res>
    implements _$SettingsStateCopyWith<$Res> {
  __$SettingsStateCopyWithImpl(this._self, this._then);

  final _SettingsState _self;
  final $Res Function(_SettingsState) _then;

  /// Create a copy of SettingsState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? gaplessPlayback = null,
    Object? crossfadeSeconds = null,
    Object? minDurationSec = null,
    Object? dynamicThemingEnabled = null,
    Object? resumeAfterInterruption = null,
    Object? waveformSeekBarEnabled = null,
    Object? themeMode = null,
    Object? customAccentColorValue = null,
    Object? playerThemeMode = null,
    Object? visualizerStyle = null,
    Object? miniPlayerSwipeLeft = null,
    Object? miniPlayerSwipeRight = null,
    Object? nowPlayingDoubleTap = null,
    Object? nowPlayingArtworkSwipe = null,
    Object? isScanning = null,
    Object? scanResultCount = freezed,
    Object? errorMessage = freezed,
  }) {
    return _then(_SettingsState(
      gaplessPlayback: null == gaplessPlayback
          ? _self.gaplessPlayback
          : gaplessPlayback // ignore: cast_nullable_to_non_nullable
              as bool,
      crossfadeSeconds: null == crossfadeSeconds
          ? _self.crossfadeSeconds
          : crossfadeSeconds // ignore: cast_nullable_to_non_nullable
              as double,
      minDurationSec: null == minDurationSec
          ? _self.minDurationSec
          : minDurationSec // ignore: cast_nullable_to_non_nullable
              as int,
      dynamicThemingEnabled: null == dynamicThemingEnabled
          ? _self.dynamicThemingEnabled
          : dynamicThemingEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      resumeAfterInterruption: null == resumeAfterInterruption
          ? _self.resumeAfterInterruption
          : resumeAfterInterruption // ignore: cast_nullable_to_non_nullable
              as bool,
      waveformSeekBarEnabled: null == waveformSeekBarEnabled
          ? _self.waveformSeekBarEnabled
          : waveformSeekBarEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      themeMode: null == themeMode
          ? _self.themeMode
          : themeMode // ignore: cast_nullable_to_non_nullable
              as AppThemeMode,
      customAccentColorValue: null == customAccentColorValue
          ? _self.customAccentColorValue
          : customAccentColorValue // ignore: cast_nullable_to_non_nullable
              as int,
      playerThemeMode: null == playerThemeMode
          ? _self.playerThemeMode
          : playerThemeMode // ignore: cast_nullable_to_non_nullable
              as PlayerThemeMode,
      visualizerStyle: null == visualizerStyle
          ? _self.visualizerStyle
          : visualizerStyle // ignore: cast_nullable_to_non_nullable
              as VisualizerStyle,
      miniPlayerSwipeLeft: null == miniPlayerSwipeLeft
          ? _self.miniPlayerSwipeLeft
          : miniPlayerSwipeLeft // ignore: cast_nullable_to_non_nullable
              as MiniPlayerSwipeAction,
      miniPlayerSwipeRight: null == miniPlayerSwipeRight
          ? _self.miniPlayerSwipeRight
          : miniPlayerSwipeRight // ignore: cast_nullable_to_non_nullable
              as MiniPlayerSwipeAction,
      nowPlayingDoubleTap: null == nowPlayingDoubleTap
          ? _self.nowPlayingDoubleTap
          : nowPlayingDoubleTap // ignore: cast_nullable_to_non_nullable
              as NowPlayingDoubleTapAction,
      nowPlayingArtworkSwipe: null == nowPlayingArtworkSwipe
          ? _self.nowPlayingArtworkSwipe
          : nowPlayingArtworkSwipe // ignore: cast_nullable_to_non_nullable
              as NowPlayingArtworkSwipeAction,
      isScanning: null == isScanning
          ? _self.isScanning
          : isScanning // ignore: cast_nullable_to_non_nullable
              as bool,
      scanResultCount: freezed == scanResultCount
          ? _self.scanResultCount
          : scanResultCount // ignore: cast_nullable_to_non_nullable
              as int?,
      errorMessage: freezed == errorMessage
          ? _self.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

// dart format on
