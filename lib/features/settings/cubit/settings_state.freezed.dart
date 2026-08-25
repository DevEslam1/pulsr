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
  bool get autoHideSystemMedia;
  ThemeColorSource get themeColorSource;
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
  ReplayGainMode get replayGainMode;
  double get replayGainPreampWithRg;
  double get replayGainPreampWithoutRg;
  YtmAudioQuality get streamingQuality;
  YtmAudioQuality get downloadQuality;
  bool get wifiOnlyMode;
  bool get offlineOnlyMode;
  bool get isScanning; // Proxy Settings
  bool get proxyEnabled;
  AppProxyType get proxyType;
  String get proxyHost;
  int get proxyPort;
  String get proxyUsername;
  String get proxyPassword;
  String get proxyBypassHosts;
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
            (identical(other.autoHideSystemMedia, autoHideSystemMedia) ||
                other.autoHideSystemMedia == autoHideSystemMedia) &&
            (identical(other.themeColorSource, themeColorSource) ||
                other.themeColorSource == themeColorSource) &&
            (identical(other.resumeAfterInterruption, resumeAfterInterruption) ||
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
            (identical(other.replayGainMode, replayGainMode) ||
                other.replayGainMode == replayGainMode) &&
            (identical(other.replayGainPreampWithRg, replayGainPreampWithRg) ||
                other.replayGainPreampWithRg == replayGainPreampWithRg) &&
            (identical(other.replayGainPreampWithoutRg, replayGainPreampWithoutRg) ||
                other.replayGainPreampWithoutRg == replayGainPreampWithoutRg) &&
            (identical(other.streamingQuality, streamingQuality) ||
                other.streamingQuality == streamingQuality) &&
            (identical(other.downloadQuality, downloadQuality) ||
                other.downloadQuality == downloadQuality) &&
            (identical(other.wifiOnlyMode, wifiOnlyMode) ||
                other.wifiOnlyMode == wifiOnlyMode) &&
            (identical(other.offlineOnlyMode, offlineOnlyMode) ||
                other.offlineOnlyMode == offlineOnlyMode) &&
            (identical(other.isScanning, isScanning) ||
                other.isScanning == isScanning) &&
            (identical(other.proxyEnabled, proxyEnabled) ||
                other.proxyEnabled == proxyEnabled) &&
            (identical(other.proxyType, proxyType) ||
                other.proxyType == proxyType) &&
            (identical(other.proxyHost, proxyHost) ||
                other.proxyHost == proxyHost) &&
            (identical(other.proxyPort, proxyPort) ||
                other.proxyPort == proxyPort) &&
            (identical(other.proxyUsername, proxyUsername) ||
                other.proxyUsername == proxyUsername) &&
            (identical(other.proxyPassword, proxyPassword) ||
                other.proxyPassword == proxyPassword) &&
            (identical(other.proxyBypassHosts, proxyBypassHosts) ||
                other.proxyBypassHosts == proxyBypassHosts) &&
            (identical(other.scanResultCount, scanResultCount) ||
                other.scanResultCount == scanResultCount) &&
            (identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
  }

  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        gaplessPlayback,
        crossfadeSeconds,
        minDurationSec,
        autoHideSystemMedia,
        themeColorSource,
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
        replayGainMode,
        replayGainPreampWithRg,
        replayGainPreampWithoutRg,
        streamingQuality,
        downloadQuality,
        wifiOnlyMode,
        offlineOnlyMode,
        isScanning,
        proxyEnabled,
        proxyType,
        proxyHost,
        proxyPort,
        proxyUsername,
        proxyPassword,
        proxyBypassHosts,
        scanResultCount,
        errorMessage
      ]);

  @override
  String toString() {
    return 'SettingsState(gaplessPlayback: $gaplessPlayback, crossfadeSeconds: $crossfadeSeconds, minDurationSec: $minDurationSec, autoHideSystemMedia: $autoHideSystemMedia, themeColorSource: $themeColorSource, resumeAfterInterruption: $resumeAfterInterruption, waveformSeekBarEnabled: $waveformSeekBarEnabled, themeMode: $themeMode, customAccentColorValue: $customAccentColorValue, playerThemeMode: $playerThemeMode, visualizerStyle: $visualizerStyle, miniPlayerSwipeLeft: $miniPlayerSwipeLeft, miniPlayerSwipeRight: $miniPlayerSwipeRight, nowPlayingDoubleTap: $nowPlayingDoubleTap, nowPlayingArtworkSwipe: $nowPlayingArtworkSwipe, replayGainMode: $replayGainMode, replayGainPreampWithRg: $replayGainPreampWithRg, replayGainPreampWithoutRg: $replayGainPreampWithoutRg, streamingQuality: $streamingQuality, downloadQuality: $downloadQuality, wifiOnlyMode: $wifiOnlyMode, offlineOnlyMode: $offlineOnlyMode, isScanning: $isScanning, proxyEnabled: $proxyEnabled, proxyType: $proxyType, proxyHost: $proxyHost, proxyPort: $proxyPort, proxyUsername: $proxyUsername, proxyPassword: $proxyPassword, proxyBypassHosts: $proxyBypassHosts, scanResultCount: $scanResultCount, errorMessage: $errorMessage)';
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
      bool autoHideSystemMedia,
      ThemeColorSource themeColorSource,
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
      ReplayGainMode replayGainMode,
      double replayGainPreampWithRg,
      double replayGainPreampWithoutRg,
      YtmAudioQuality streamingQuality,
      YtmAudioQuality downloadQuality,
      bool wifiOnlyMode,
      bool offlineOnlyMode,
      bool isScanning,
      bool proxyEnabled,
      AppProxyType proxyType,
      String proxyHost,
      int proxyPort,
      String proxyUsername,
      String proxyPassword,
      String proxyBypassHosts,
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
    Object? autoHideSystemMedia = null,
    Object? themeColorSource = null,
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
    Object? replayGainMode = null,
    Object? replayGainPreampWithRg = null,
    Object? replayGainPreampWithoutRg = null,
    Object? streamingQuality = null,
    Object? downloadQuality = null,
    Object? wifiOnlyMode = null,
    Object? offlineOnlyMode = null,
    Object? isScanning = null,
    Object? proxyEnabled = null,
    Object? proxyType = null,
    Object? proxyHost = null,
    Object? proxyPort = null,
    Object? proxyUsername = null,
    Object? proxyPassword = null,
    Object? proxyBypassHosts = null,
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
      autoHideSystemMedia: null == autoHideSystemMedia
          ? _self.autoHideSystemMedia
          : autoHideSystemMedia // ignore: cast_nullable_to_non_nullable
              as bool,
      themeColorSource: null == themeColorSource
          ? _self.themeColorSource
          : themeColorSource // ignore: cast_nullable_to_non_nullable
              as ThemeColorSource,
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
      replayGainMode: null == replayGainMode
          ? _self.replayGainMode
          : replayGainMode // ignore: cast_nullable_to_non_nullable
              as ReplayGainMode,
      replayGainPreampWithRg: null == replayGainPreampWithRg
          ? _self.replayGainPreampWithRg
          : replayGainPreampWithRg // ignore: cast_nullable_to_non_nullable
              as double,
      replayGainPreampWithoutRg: null == replayGainPreampWithoutRg
          ? _self.replayGainPreampWithoutRg
          : replayGainPreampWithoutRg // ignore: cast_nullable_to_non_nullable
              as double,
      streamingQuality: null == streamingQuality
          ? _self.streamingQuality
          : streamingQuality // ignore: cast_nullable_to_non_nullable
              as YtmAudioQuality,
      downloadQuality: null == downloadQuality
          ? _self.downloadQuality
          : downloadQuality // ignore: cast_nullable_to_non_nullable
              as YtmAudioQuality,
      wifiOnlyMode: null == wifiOnlyMode
          ? _self.wifiOnlyMode
          : wifiOnlyMode // ignore: cast_nullable_to_non_nullable
              as bool,
      offlineOnlyMode: null == offlineOnlyMode
          ? _self.offlineOnlyMode
          : offlineOnlyMode // ignore: cast_nullable_to_non_nullable
              as bool,
      isScanning: null == isScanning
          ? _self.isScanning
          : isScanning // ignore: cast_nullable_to_non_nullable
              as bool,
      proxyEnabled: null == proxyEnabled
          ? _self.proxyEnabled
          : proxyEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      proxyType: null == proxyType
          ? _self.proxyType
          : proxyType // ignore: cast_nullable_to_non_nullable
              as AppProxyType,
      proxyHost: null == proxyHost
          ? _self.proxyHost
          : proxyHost // ignore: cast_nullable_to_non_nullable
              as String,
      proxyPort: null == proxyPort
          ? _self.proxyPort
          : proxyPort // ignore: cast_nullable_to_non_nullable
              as int,
      proxyUsername: null == proxyUsername
          ? _self.proxyUsername
          : proxyUsername // ignore: cast_nullable_to_non_nullable
              as String,
      proxyPassword: null == proxyPassword
          ? _self.proxyPassword
          : proxyPassword // ignore: cast_nullable_to_non_nullable
              as String,
      proxyBypassHosts: null == proxyBypassHosts
          ? _self.proxyBypassHosts
          : proxyBypassHosts // ignore: cast_nullable_to_non_nullable
              as String,
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
            bool autoHideSystemMedia,
            ThemeColorSource themeColorSource,
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
            ReplayGainMode replayGainMode,
            double replayGainPreampWithRg,
            double replayGainPreampWithoutRg,
            YtmAudioQuality streamingQuality,
            YtmAudioQuality downloadQuality,
            bool wifiOnlyMode,
            bool offlineOnlyMode,
            bool isScanning,
            bool proxyEnabled,
            AppProxyType proxyType,
            String proxyHost,
            int proxyPort,
            String proxyUsername,
            String proxyPassword,
            String proxyBypassHosts,
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
            _that.autoHideSystemMedia,
            _that.themeColorSource,
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
            _that.replayGainMode,
            _that.replayGainPreampWithRg,
            _that.replayGainPreampWithoutRg,
            _that.streamingQuality,
            _that.downloadQuality,
            _that.wifiOnlyMode,
            _that.offlineOnlyMode,
            _that.isScanning,
            _that.proxyEnabled,
            _that.proxyType,
            _that.proxyHost,
            _that.proxyPort,
            _that.proxyUsername,
            _that.proxyPassword,
            _that.proxyBypassHosts,
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
            bool autoHideSystemMedia,
            ThemeColorSource themeColorSource,
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
            ReplayGainMode replayGainMode,
            double replayGainPreampWithRg,
            double replayGainPreampWithoutRg,
            YtmAudioQuality streamingQuality,
            YtmAudioQuality downloadQuality,
            bool wifiOnlyMode,
            bool offlineOnlyMode,
            bool isScanning,
            bool proxyEnabled,
            AppProxyType proxyType,
            String proxyHost,
            int proxyPort,
            String proxyUsername,
            String proxyPassword,
            String proxyBypassHosts,
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
            _that.autoHideSystemMedia,
            _that.themeColorSource,
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
            _that.replayGainMode,
            _that.replayGainPreampWithRg,
            _that.replayGainPreampWithoutRg,
            _that.streamingQuality,
            _that.downloadQuality,
            _that.wifiOnlyMode,
            _that.offlineOnlyMode,
            _that.isScanning,
            _that.proxyEnabled,
            _that.proxyType,
            _that.proxyHost,
            _that.proxyPort,
            _that.proxyUsername,
            _that.proxyPassword,
            _that.proxyBypassHosts,
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
            bool autoHideSystemMedia,
            ThemeColorSource themeColorSource,
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
            ReplayGainMode replayGainMode,
            double replayGainPreampWithRg,
            double replayGainPreampWithoutRg,
            YtmAudioQuality streamingQuality,
            YtmAudioQuality downloadQuality,
            bool wifiOnlyMode,
            bool offlineOnlyMode,
            bool isScanning,
            bool proxyEnabled,
            AppProxyType proxyType,
            String proxyHost,
            int proxyPort,
            String proxyUsername,
            String proxyPassword,
            String proxyBypassHosts,
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
            _that.autoHideSystemMedia,
            _that.themeColorSource,
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
            _that.replayGainMode,
            _that.replayGainPreampWithRg,
            _that.replayGainPreampWithoutRg,
            _that.streamingQuality,
            _that.downloadQuality,
            _that.wifiOnlyMode,
            _that.offlineOnlyMode,
            _that.isScanning,
            _that.proxyEnabled,
            _that.proxyType,
            _that.proxyHost,
            _that.proxyPort,
            _that.proxyUsername,
            _that.proxyPassword,
            _that.proxyBypassHosts,
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
      this.autoHideSystemMedia = true,
      this.themeColorSource = ThemeColorSource.artwork,
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
      this.replayGainMode = ReplayGainMode.track,
      this.replayGainPreampWithRg = 0.0,
      this.replayGainPreampWithoutRg = -3.0,
      this.streamingQuality = YtmAudioQuality.high,
      this.downloadQuality = YtmAudioQuality.high,
      this.wifiOnlyMode = false,
      this.offlineOnlyMode = false,
      this.isScanning = false,
      this.proxyEnabled = false,
      this.proxyType = AppProxyType.http,
      this.proxyHost = '',
      this.proxyPort = 8080,
      this.proxyUsername = '',
      this.proxyPassword = '',
      this.proxyBypassHosts = 'localhost, 127.0.0.1',
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
  final bool autoHideSystemMedia;
  @override
  @JsonKey()
  final ThemeColorSource themeColorSource;
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
  final ReplayGainMode replayGainMode;
  @override
  @JsonKey()
  final double replayGainPreampWithRg;
  @override
  @JsonKey()
  final double replayGainPreampWithoutRg;
  @override
  @JsonKey()
  final YtmAudioQuality streamingQuality;
  @override
  @JsonKey()
  final YtmAudioQuality downloadQuality;
  @override
  @JsonKey()
  final bool wifiOnlyMode;
  @override
  @JsonKey()
  final bool offlineOnlyMode;
  @override
  @JsonKey()
  final bool isScanning;
// Proxy Settings
  @override
  @JsonKey()
  final bool proxyEnabled;
  @override
  @JsonKey()
  final AppProxyType proxyType;
  @override
  @JsonKey()
  final String proxyHost;
  @override
  @JsonKey()
  final int proxyPort;
  @override
  @JsonKey()
  final String proxyUsername;
  @override
  @JsonKey()
  final String proxyPassword;
  @override
  @JsonKey()
  final String proxyBypassHosts;
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
            (identical(other.autoHideSystemMedia, autoHideSystemMedia) ||
                other.autoHideSystemMedia == autoHideSystemMedia) &&
            (identical(other.themeColorSource, themeColorSource) ||
                other.themeColorSource == themeColorSource) &&
            (identical(other.resumeAfterInterruption, resumeAfterInterruption) ||
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
            (identical(other.replayGainMode, replayGainMode) ||
                other.replayGainMode == replayGainMode) &&
            (identical(other.replayGainPreampWithRg, replayGainPreampWithRg) ||
                other.replayGainPreampWithRg == replayGainPreampWithRg) &&
            (identical(other.replayGainPreampWithoutRg, replayGainPreampWithoutRg) ||
                other.replayGainPreampWithoutRg == replayGainPreampWithoutRg) &&
            (identical(other.streamingQuality, streamingQuality) ||
                other.streamingQuality == streamingQuality) &&
            (identical(other.downloadQuality, downloadQuality) ||
                other.downloadQuality == downloadQuality) &&
            (identical(other.wifiOnlyMode, wifiOnlyMode) ||
                other.wifiOnlyMode == wifiOnlyMode) &&
            (identical(other.offlineOnlyMode, offlineOnlyMode) ||
                other.offlineOnlyMode == offlineOnlyMode) &&
            (identical(other.isScanning, isScanning) ||
                other.isScanning == isScanning) &&
            (identical(other.proxyEnabled, proxyEnabled) ||
                other.proxyEnabled == proxyEnabled) &&
            (identical(other.proxyType, proxyType) ||
                other.proxyType == proxyType) &&
            (identical(other.proxyHost, proxyHost) ||
                other.proxyHost == proxyHost) &&
            (identical(other.proxyPort, proxyPort) ||
                other.proxyPort == proxyPort) &&
            (identical(other.proxyUsername, proxyUsername) ||
                other.proxyUsername == proxyUsername) &&
            (identical(other.proxyPassword, proxyPassword) ||
                other.proxyPassword == proxyPassword) &&
            (identical(other.proxyBypassHosts, proxyBypassHosts) ||
                other.proxyBypassHosts == proxyBypassHosts) &&
            (identical(other.scanResultCount, scanResultCount) ||
                other.scanResultCount == scanResultCount) &&
            (identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
  }

  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        gaplessPlayback,
        crossfadeSeconds,
        minDurationSec,
        autoHideSystemMedia,
        themeColorSource,
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
        replayGainMode,
        replayGainPreampWithRg,
        replayGainPreampWithoutRg,
        streamingQuality,
        downloadQuality,
        wifiOnlyMode,
        offlineOnlyMode,
        isScanning,
        proxyEnabled,
        proxyType,
        proxyHost,
        proxyPort,
        proxyUsername,
        proxyPassword,
        proxyBypassHosts,
        scanResultCount,
        errorMessage
      ]);

  @override
  String toString() {
    return 'SettingsState(gaplessPlayback: $gaplessPlayback, crossfadeSeconds: $crossfadeSeconds, minDurationSec: $minDurationSec, autoHideSystemMedia: $autoHideSystemMedia, themeColorSource: $themeColorSource, resumeAfterInterruption: $resumeAfterInterruption, waveformSeekBarEnabled: $waveformSeekBarEnabled, themeMode: $themeMode, customAccentColorValue: $customAccentColorValue, playerThemeMode: $playerThemeMode, visualizerStyle: $visualizerStyle, miniPlayerSwipeLeft: $miniPlayerSwipeLeft, miniPlayerSwipeRight: $miniPlayerSwipeRight, nowPlayingDoubleTap: $nowPlayingDoubleTap, nowPlayingArtworkSwipe: $nowPlayingArtworkSwipe, replayGainMode: $replayGainMode, replayGainPreampWithRg: $replayGainPreampWithRg, replayGainPreampWithoutRg: $replayGainPreampWithoutRg, streamingQuality: $streamingQuality, downloadQuality: $downloadQuality, wifiOnlyMode: $wifiOnlyMode, offlineOnlyMode: $offlineOnlyMode, isScanning: $isScanning, proxyEnabled: $proxyEnabled, proxyType: $proxyType, proxyHost: $proxyHost, proxyPort: $proxyPort, proxyUsername: $proxyUsername, proxyPassword: $proxyPassword, proxyBypassHosts: $proxyBypassHosts, scanResultCount: $scanResultCount, errorMessage: $errorMessage)';
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
      bool autoHideSystemMedia,
      ThemeColorSource themeColorSource,
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
      ReplayGainMode replayGainMode,
      double replayGainPreampWithRg,
      double replayGainPreampWithoutRg,
      YtmAudioQuality streamingQuality,
      YtmAudioQuality downloadQuality,
      bool wifiOnlyMode,
      bool offlineOnlyMode,
      bool isScanning,
      bool proxyEnabled,
      AppProxyType proxyType,
      String proxyHost,
      int proxyPort,
      String proxyUsername,
      String proxyPassword,
      String proxyBypassHosts,
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
    Object? autoHideSystemMedia = null,
    Object? themeColorSource = null,
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
    Object? replayGainMode = null,
    Object? replayGainPreampWithRg = null,
    Object? replayGainPreampWithoutRg = null,
    Object? streamingQuality = null,
    Object? downloadQuality = null,
    Object? wifiOnlyMode = null,
    Object? offlineOnlyMode = null,
    Object? isScanning = null,
    Object? proxyEnabled = null,
    Object? proxyType = null,
    Object? proxyHost = null,
    Object? proxyPort = null,
    Object? proxyUsername = null,
    Object? proxyPassword = null,
    Object? proxyBypassHosts = null,
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
      autoHideSystemMedia: null == autoHideSystemMedia
          ? _self.autoHideSystemMedia
          : autoHideSystemMedia // ignore: cast_nullable_to_non_nullable
              as bool,
      themeColorSource: null == themeColorSource
          ? _self.themeColorSource
          : themeColorSource // ignore: cast_nullable_to_non_nullable
              as ThemeColorSource,
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
      replayGainMode: null == replayGainMode
          ? _self.replayGainMode
          : replayGainMode // ignore: cast_nullable_to_non_nullable
              as ReplayGainMode,
      replayGainPreampWithRg: null == replayGainPreampWithRg
          ? _self.replayGainPreampWithRg
          : replayGainPreampWithRg // ignore: cast_nullable_to_non_nullable
              as double,
      replayGainPreampWithoutRg: null == replayGainPreampWithoutRg
          ? _self.replayGainPreampWithoutRg
          : replayGainPreampWithoutRg // ignore: cast_nullable_to_non_nullable
              as double,
      streamingQuality: null == streamingQuality
          ? _self.streamingQuality
          : streamingQuality // ignore: cast_nullable_to_non_nullable
              as YtmAudioQuality,
      downloadQuality: null == downloadQuality
          ? _self.downloadQuality
          : downloadQuality // ignore: cast_nullable_to_non_nullable
              as YtmAudioQuality,
      wifiOnlyMode: null == wifiOnlyMode
          ? _self.wifiOnlyMode
          : wifiOnlyMode // ignore: cast_nullable_to_non_nullable
              as bool,
      offlineOnlyMode: null == offlineOnlyMode
          ? _self.offlineOnlyMode
          : offlineOnlyMode // ignore: cast_nullable_to_non_nullable
              as bool,
      isScanning: null == isScanning
          ? _self.isScanning
          : isScanning // ignore: cast_nullable_to_non_nullable
              as bool,
      proxyEnabled: null == proxyEnabled
          ? _self.proxyEnabled
          : proxyEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      proxyType: null == proxyType
          ? _self.proxyType
          : proxyType // ignore: cast_nullable_to_non_nullable
              as AppProxyType,
      proxyHost: null == proxyHost
          ? _self.proxyHost
          : proxyHost // ignore: cast_nullable_to_non_nullable
              as String,
      proxyPort: null == proxyPort
          ? _self.proxyPort
          : proxyPort // ignore: cast_nullable_to_non_nullable
              as int,
      proxyUsername: null == proxyUsername
          ? _self.proxyUsername
          : proxyUsername // ignore: cast_nullable_to_non_nullable
              as String,
      proxyPassword: null == proxyPassword
          ? _self.proxyPassword
          : proxyPassword // ignore: cast_nullable_to_non_nullable
              as String,
      proxyBypassHosts: null == proxyBypassHosts
          ? _self.proxyBypassHosts
          : proxyBypassHosts // ignore: cast_nullable_to_non_nullable
              as String,
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
