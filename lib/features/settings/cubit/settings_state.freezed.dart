// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'settings_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
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
  bool get autoThemeByTime;
  bool get highContrast;
  bool get reduceMotion;
  double get liquidGlassTint;
  String get languageCode;
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
  bool get isScanning;
  bool get proxyEnabled;
  AppProxyType get proxyType;
  String get proxyHost;
  int get proxyPort;
  String get proxyUsername;
  bool get hasProxyPassword;
  String get proxyBypassHosts;
  List<ProxyEntry> get proxyList;
  bool get isTestingAllProxies;
  ExtractorEngine get extractorEngine;
  bool get ytdlpBackendEnabled;
  String get ytdlpBackendUrl;
  String get ytdlpBackendToken;
  bool get syncCookiesToBackend;
  bool get isTestingYtdlpBackend;
  String? get ytdlpBackendStatusMessage;
  String? get ytdlpBackendVersion;
  int? get ytdlpBackendProxyCount;
  String? get ytdlpBackendCircuitState;
  bool get bitPerfectOutput;
  bool get bypassDspOnBitPerfect;
  bool get followTrackSampleRate;
  bool get strictBitPerfect;
  DsdOutputMode get dsdOutputMode;
  ExperienceMode get experienceMode;
  bool get dsdDopSupported;
  AudioOutputInfo? get currentOutputDevice;
  int? get scanResultCount;
  String? get errorMessage;
  bool get crossfeedEnabled;
  double get crossfeedDelayUs;
  double get crossfeedFeedDb;
  bool get limiterEnabled;
  double get limiterLookaheadMs;
  double get limiterThresholdDb;
  double get limiterReleaseMs;
  bool get reverbEnabled;
  int get reverbPreset;
  double get reverbWetDry;
  double get stereoBalance;
  bool get monoMix;
  bool get sincResamplerEnabled;
  String get dspPreference;
  String get systemEffectsPolicy;
  String get systemEffectsStatus;
  List<String> get systemEffectsBundles;
  int get bluetoothLatencyOffsetMs;
  bool get hedgedResolutionEnabled;
  bool get adaptiveQualityEnabled;
  String get duckingMode;
  double get duckingLevel;
  String get multiOutputMode;
  bool get dspSnapshotEnabled;
  int get silenceSkipSensitivity;
  bool get sessionLogEnabled;
  bool get outputFormatNegotiationEnabled;
  bool get floatOutputEnabled;
  bool get aaudioOutputEnabled;
  bool get dvcEnabled;
  bool get usbHardwareVolumeEnabled;
  bool get aaudioPreferExclusive;
  int get aaudioTargetBufferMs;
  int get sincResamplerQuality;
  bool get bpmSyncCrossfadeEnabled;

  /// Create a copy of SettingsState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $SettingsStateCopyWith<SettingsState> get copyWith =>
      _$SettingsStateCopyWithImpl<SettingsState>(
          this as SettingsState, _$identity);

  @override
  bool operator ==(Object other) {
    final _this = this as SettingsState;
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is SettingsState &&
            (identical(other.gaplessPlayback, _this.gaplessPlayback) ||
                other.gaplessPlayback == _this.gaplessPlayback) &&
            (identical(other.crossfadeSeconds, _this.crossfadeSeconds) ||
                other.crossfadeSeconds == _this.crossfadeSeconds) &&
            (identical(other.minDurationSec, _this.minDurationSec) ||
                other.minDurationSec == _this.minDurationSec) &&
            (identical(other.autoHideSystemMedia, _this.autoHideSystemMedia) ||
                other.autoHideSystemMedia == _this.autoHideSystemMedia) &&
            (identical(other.themeColorSource, _this.themeColorSource) ||
                other.themeColorSource == _this.themeColorSource) &&
            (identical(other.resumeAfterInterruption, _this.resumeAfterInterruption) ||
                other.resumeAfterInterruption ==
                    _this.resumeAfterInterruption) &&
            (identical(other.waveformSeekBarEnabled, _this.waveformSeekBarEnabled) ||
                other.waveformSeekBarEnabled == _this.waveformSeekBarEnabled) &&
            (identical(other.themeMode, _this.themeMode) ||
                other.themeMode == _this.themeMode) &&
            (identical(other.autoThemeByTime, _this.autoThemeByTime) ||
                other.autoThemeByTime == _this.autoThemeByTime) &&
            (identical(other.highContrast, _this.highContrast) ||
                other.highContrast == _this.highContrast) &&
            (identical(other.reduceMotion, _this.reduceMotion) ||
                other.reduceMotion == _this.reduceMotion) &&
            (identical(other.liquidGlassTint, _this.liquidGlassTint) ||
                other.liquidGlassTint == _this.liquidGlassTint) &&
            (identical(other.languageCode, _this.languageCode) ||
                other.languageCode == _this.languageCode) &&
            (identical(other.customAccentColorValue, _this.customAccentColorValue) ||
                other.customAccentColorValue == _this.customAccentColorValue) &&
            (identical(other.playerThemeMode, _this.playerThemeMode) ||
                other.playerThemeMode == _this.playerThemeMode) &&
            (identical(other.visualizerStyle, _this.visualizerStyle) ||
                other.visualizerStyle == _this.visualizerStyle) &&
            (identical(other.miniPlayerSwipeLeft, _this.miniPlayerSwipeLeft) ||
                other.miniPlayerSwipeLeft == _this.miniPlayerSwipeLeft) &&
            (identical(other.miniPlayerSwipeRight, _this.miniPlayerSwipeRight) ||
                other.miniPlayerSwipeRight == _this.miniPlayerSwipeRight) &&
            (identical(other.nowPlayingDoubleTap, _this.nowPlayingDoubleTap) ||
                other.nowPlayingDoubleTap == _this.nowPlayingDoubleTap) &&
            (identical(other.nowPlayingArtworkSwipe, _this.nowPlayingArtworkSwipe) ||
                other.nowPlayingArtworkSwipe == _this.nowPlayingArtworkSwipe) &&
            (identical(other.replayGainMode, _this.replayGainMode) ||
                other.replayGainMode == _this.replayGainMode) &&
            (identical(other.replayGainPreampWithRg, _this.replayGainPreampWithRg) ||
                other.replayGainPreampWithRg == _this.replayGainPreampWithRg) &&
            (identical(other.replayGainPreampWithoutRg, _this.replayGainPreampWithoutRg) ||
                other.replayGainPreampWithoutRg ==
                    _this.replayGainPreampWithoutRg) &&
            (identical(other.streamingQuality, _this.streamingQuality) ||
                other.streamingQuality == _this.streamingQuality) &&
            (identical(other.downloadQuality, _this.downloadQuality) ||
                other.downloadQuality == _this.downloadQuality) &&
            (identical(other.wifiOnlyMode, _this.wifiOnlyMode) ||
                other.wifiOnlyMode == _this.wifiOnlyMode) &&
            (identical(other.offlineOnlyMode, _this.offlineOnlyMode) || other.offlineOnlyMode == _this.offlineOnlyMode) &&
            (identical(other.isScanning, _this.isScanning) || other.isScanning == _this.isScanning) &&
            (identical(other.proxyEnabled, _this.proxyEnabled) || other.proxyEnabled == _this.proxyEnabled) &&
            (identical(other.proxyType, _this.proxyType) || other.proxyType == _this.proxyType) &&
            (identical(other.proxyHost, _this.proxyHost) || other.proxyHost == _this.proxyHost) &&
            (identical(other.proxyPort, _this.proxyPort) || other.proxyPort == _this.proxyPort) &&
            (identical(other.proxyUsername, _this.proxyUsername) || other.proxyUsername == _this.proxyUsername) &&
            (identical(other.hasProxyPassword, _this.hasProxyPassword) || other.hasProxyPassword == _this.hasProxyPassword) &&
            (identical(other.proxyBypassHosts, _this.proxyBypassHosts) || other.proxyBypassHosts == _this.proxyBypassHosts) &&
            const DeepCollectionEquality().equals(other.proxyList, _this.proxyList) &&
            (identical(other.isTestingAllProxies, _this.isTestingAllProxies) || other.isTestingAllProxies == _this.isTestingAllProxies) &&
            (identical(other.extractorEngine, _this.extractorEngine) || other.extractorEngine == _this.extractorEngine) &&
            (identical(other.ytdlpBackendEnabled, _this.ytdlpBackendEnabled) || other.ytdlpBackendEnabled == _this.ytdlpBackendEnabled) &&
            (identical(other.ytdlpBackendUrl, _this.ytdlpBackendUrl) || other.ytdlpBackendUrl == _this.ytdlpBackendUrl) &&
            (identical(other.ytdlpBackendToken, _this.ytdlpBackendToken) || other.ytdlpBackendToken == _this.ytdlpBackendToken) &&
            (identical(other.syncCookiesToBackend, _this.syncCookiesToBackend) || other.syncCookiesToBackend == _this.syncCookiesToBackend) &&
            (identical(other.isTestingYtdlpBackend, _this.isTestingYtdlpBackend) || other.isTestingYtdlpBackend == _this.isTestingYtdlpBackend) &&
            (identical(other.ytdlpBackendStatusMessage, _this.ytdlpBackendStatusMessage) || other.ytdlpBackendStatusMessage == _this.ytdlpBackendStatusMessage) &&
            (identical(other.ytdlpBackendVersion, _this.ytdlpBackendVersion) || other.ytdlpBackendVersion == _this.ytdlpBackendVersion) &&
            (identical(other.ytdlpBackendProxyCount, _this.ytdlpBackendProxyCount) || other.ytdlpBackendProxyCount == _this.ytdlpBackendProxyCount) &&
            (identical(other.ytdlpBackendCircuitState, _this.ytdlpBackendCircuitState) || other.ytdlpBackendCircuitState == _this.ytdlpBackendCircuitState) &&
            (identical(other.bitPerfectOutput, _this.bitPerfectOutput) || other.bitPerfectOutput == _this.bitPerfectOutput) &&
            (identical(other.bypassDspOnBitPerfect, _this.bypassDspOnBitPerfect) || other.bypassDspOnBitPerfect == _this.bypassDspOnBitPerfect) &&
            (identical(other.followTrackSampleRate, _this.followTrackSampleRate) || other.followTrackSampleRate == _this.followTrackSampleRate) &&
            (identical(other.strictBitPerfect, _this.strictBitPerfect) || other.strictBitPerfect == _this.strictBitPerfect) &&
            (identical(other.dsdOutputMode, _this.dsdOutputMode) || other.dsdOutputMode == _this.dsdOutputMode) &&
            (identical(other.experienceMode, _this.experienceMode) || other.experienceMode == _this.experienceMode) &&
            (identical(other.dsdDopSupported, _this.dsdDopSupported) || other.dsdDopSupported == _this.dsdDopSupported) &&
            (identical(other.currentOutputDevice, _this.currentOutputDevice) || other.currentOutputDevice == _this.currentOutputDevice) &&
            (identical(other.scanResultCount, _this.scanResultCount) || other.scanResultCount == _this.scanResultCount) &&
            (identical(other.errorMessage, _this.errorMessage) || other.errorMessage == _this.errorMessage) &&
            (identical(other.crossfeedEnabled, _this.crossfeedEnabled) || other.crossfeedEnabled == _this.crossfeedEnabled) &&
            (identical(other.crossfeedDelayUs, _this.crossfeedDelayUs) || other.crossfeedDelayUs == _this.crossfeedDelayUs) &&
            (identical(other.crossfeedFeedDb, _this.crossfeedFeedDb) || other.crossfeedFeedDb == _this.crossfeedFeedDb) &&
            (identical(other.limiterEnabled, _this.limiterEnabled) || other.limiterEnabled == _this.limiterEnabled) &&
            (identical(other.limiterLookaheadMs, _this.limiterLookaheadMs) || other.limiterLookaheadMs == _this.limiterLookaheadMs) &&
            (identical(other.limiterThresholdDb, _this.limiterThresholdDb) || other.limiterThresholdDb == _this.limiterThresholdDb) &&
            (identical(other.limiterReleaseMs, _this.limiterReleaseMs) || other.limiterReleaseMs == _this.limiterReleaseMs) &&
            (identical(other.reverbEnabled, _this.reverbEnabled) || other.reverbEnabled == _this.reverbEnabled) &&
            (identical(other.reverbPreset, _this.reverbPreset) || other.reverbPreset == _this.reverbPreset) &&
            (identical(other.reverbWetDry, _this.reverbWetDry) || other.reverbWetDry == _this.reverbWetDry) &&
            (identical(other.stereoBalance, _this.stereoBalance) || other.stereoBalance == _this.stereoBalance) &&
            (identical(other.monoMix, _this.monoMix) || other.monoMix == _this.monoMix) &&
            (identical(other.sincResamplerEnabled, _this.sincResamplerEnabled) || other.sincResamplerEnabled == _this.sincResamplerEnabled) &&
            (identical(other.dspPreference, _this.dspPreference) || other.dspPreference == _this.dspPreference) &&
            (identical(other.systemEffectsPolicy, _this.systemEffectsPolicy) || other.systemEffectsPolicy == _this.systemEffectsPolicy) &&
            (identical(other.systemEffectsStatus, _this.systemEffectsStatus) || other.systemEffectsStatus == _this.systemEffectsStatus) &&
            const DeepCollectionEquality().equals(other.systemEffectsBundles, _this.systemEffectsBundles) &&
            (identical(other.bluetoothLatencyOffsetMs, _this.bluetoothLatencyOffsetMs) || other.bluetoothLatencyOffsetMs == _this.bluetoothLatencyOffsetMs) &&
            (identical(other.hedgedResolutionEnabled, _this.hedgedResolutionEnabled) || other.hedgedResolutionEnabled == _this.hedgedResolutionEnabled) &&
            (identical(other.adaptiveQualityEnabled, _this.adaptiveQualityEnabled) || other.adaptiveQualityEnabled == _this.adaptiveQualityEnabled) &&
            (identical(other.duckingMode, _this.duckingMode) || other.duckingMode == _this.duckingMode) &&
            (identical(other.duckingLevel, _this.duckingLevel) || other.duckingLevel == _this.duckingLevel) &&
            (identical(other.multiOutputMode, _this.multiOutputMode) || other.multiOutputMode == _this.multiOutputMode) &&
            (identical(other.dspSnapshotEnabled, _this.dspSnapshotEnabled) || other.dspSnapshotEnabled == _this.dspSnapshotEnabled) &&
            (identical(other.silenceSkipSensitivity, _this.silenceSkipSensitivity) || other.silenceSkipSensitivity == _this.silenceSkipSensitivity) &&
            (identical(other.sessionLogEnabled, _this.sessionLogEnabled) || other.sessionLogEnabled == _this.sessionLogEnabled) &&
            (identical(other.outputFormatNegotiationEnabled, _this.outputFormatNegotiationEnabled) || other.outputFormatNegotiationEnabled == _this.outputFormatNegotiationEnabled) &&
            (identical(other.floatOutputEnabled, _this.floatOutputEnabled) || other.floatOutputEnabled == _this.floatOutputEnabled) &&
            (identical(other.aaudioOutputEnabled, _this.aaudioOutputEnabled) || other.aaudioOutputEnabled == _this.aaudioOutputEnabled) &&
            (identical(other.dvcEnabled, _this.dvcEnabled) || other.dvcEnabled == _this.dvcEnabled) &&
            (identical(other.usbHardwareVolumeEnabled, _this.usbHardwareVolumeEnabled) || other.usbHardwareVolumeEnabled == _this.usbHardwareVolumeEnabled) &&
            (identical(other.aaudioPreferExclusive, _this.aaudioPreferExclusive) || other.aaudioPreferExclusive == _this.aaudioPreferExclusive) &&
            (identical(other.aaudioTargetBufferMs, _this.aaudioTargetBufferMs) || other.aaudioTargetBufferMs == _this.aaudioTargetBufferMs) &&
            (identical(other.sincResamplerQuality, _this.sincResamplerQuality) || other.sincResamplerQuality == _this.sincResamplerQuality) &&
            (identical(other.bpmSyncCrossfadeEnabled, _this.bpmSyncCrossfadeEnabled) || other.bpmSyncCrossfadeEnabled == _this.bpmSyncCrossfadeEnabled));
  }

  @override
  int get hashCode {
    final _this = this as SettingsState;
    return Object.hashAll([
      runtimeType,
      _this.gaplessPlayback,
      _this.crossfadeSeconds,
      _this.minDurationSec,
      _this.autoHideSystemMedia,
      _this.themeColorSource,
      _this.resumeAfterInterruption,
      _this.waveformSeekBarEnabled,
      _this.themeMode,
      _this.autoThemeByTime,
      _this.highContrast,
      _this.reduceMotion,
      _this.liquidGlassTint,
      _this.languageCode,
      _this.customAccentColorValue,
      _this.playerThemeMode,
      _this.visualizerStyle,
      _this.miniPlayerSwipeLeft,
      _this.miniPlayerSwipeRight,
      _this.nowPlayingDoubleTap,
      _this.nowPlayingArtworkSwipe,
      _this.replayGainMode,
      _this.replayGainPreampWithRg,
      _this.replayGainPreampWithoutRg,
      _this.streamingQuality,
      _this.downloadQuality,
      _this.wifiOnlyMode,
      _this.offlineOnlyMode,
      _this.isScanning,
      _this.proxyEnabled,
      _this.proxyType,
      _this.proxyHost,
      _this.proxyPort,
      _this.proxyUsername,
      _this.hasProxyPassword,
      _this.proxyBypassHosts,
      const DeepCollectionEquality().hash(_this.proxyList),
      _this.isTestingAllProxies,
      _this.extractorEngine,
      _this.ytdlpBackendEnabled,
      _this.ytdlpBackendUrl,
      _this.ytdlpBackendToken,
      _this.syncCookiesToBackend,
      _this.isTestingYtdlpBackend,
      _this.ytdlpBackendStatusMessage,
      _this.ytdlpBackendVersion,
      _this.ytdlpBackendProxyCount,
      _this.ytdlpBackendCircuitState,
      _this.bitPerfectOutput,
      _this.bypassDspOnBitPerfect,
      _this.followTrackSampleRate,
      _this.strictBitPerfect,
      _this.dsdOutputMode,
      _this.experienceMode,
      _this.dsdDopSupported,
      _this.currentOutputDevice,
      _this.scanResultCount,
      _this.errorMessage,
      _this.crossfeedEnabled,
      _this.crossfeedDelayUs,
      _this.crossfeedFeedDb,
      _this.limiterEnabled,
      _this.limiterLookaheadMs,
      _this.limiterThresholdDb,
      _this.limiterReleaseMs,
      _this.reverbEnabled,
      _this.reverbPreset,
      _this.reverbWetDry,
      _this.stereoBalance,
      _this.monoMix,
      _this.sincResamplerEnabled,
      _this.dspPreference,
      _this.systemEffectsPolicy,
      _this.systemEffectsStatus,
      const DeepCollectionEquality().hash(_this.systemEffectsBundles),
      _this.bluetoothLatencyOffsetMs,
      _this.hedgedResolutionEnabled,
      _this.adaptiveQualityEnabled,
      _this.duckingMode,
      _this.duckingLevel,
      _this.multiOutputMode,
      _this.dspSnapshotEnabled,
      _this.silenceSkipSensitivity,
      _this.sessionLogEnabled,
      _this.outputFormatNegotiationEnabled,
      _this.floatOutputEnabled,
      _this.aaudioOutputEnabled,
      _this.dvcEnabled,
      _this.usbHardwareVolumeEnabled,
      _this.aaudioPreferExclusive,
      _this.aaudioTargetBufferMs,
      _this.sincResamplerQuality,
      _this.bpmSyncCrossfadeEnabled
    ]);
  }

  @override
  String toString() {
    final _this = this as SettingsState;
    return 'SettingsState(gaplessPlayback: ${_this.gaplessPlayback}, crossfadeSeconds: ${_this.crossfadeSeconds}, minDurationSec: ${_this.minDurationSec}, autoHideSystemMedia: ${_this.autoHideSystemMedia}, themeColorSource: ${_this.themeColorSource}, resumeAfterInterruption: ${_this.resumeAfterInterruption}, waveformSeekBarEnabled: ${_this.waveformSeekBarEnabled}, themeMode: ${_this.themeMode}, autoThemeByTime: ${_this.autoThemeByTime}, highContrast: ${_this.highContrast}, reduceMotion: ${_this.reduceMotion}, liquidGlassTint: ${_this.liquidGlassTint}, languageCode: ${_this.languageCode}, customAccentColorValue: ${_this.customAccentColorValue}, playerThemeMode: ${_this.playerThemeMode}, visualizerStyle: ${_this.visualizerStyle}, miniPlayerSwipeLeft: ${_this.miniPlayerSwipeLeft}, miniPlayerSwipeRight: ${_this.miniPlayerSwipeRight}, nowPlayingDoubleTap: ${_this.nowPlayingDoubleTap}, nowPlayingArtworkSwipe: ${_this.nowPlayingArtworkSwipe}, replayGainMode: ${_this.replayGainMode}, replayGainPreampWithRg: ${_this.replayGainPreampWithRg}, replayGainPreampWithoutRg: ${_this.replayGainPreampWithoutRg}, streamingQuality: ${_this.streamingQuality}, downloadQuality: ${_this.downloadQuality}, wifiOnlyMode: ${_this.wifiOnlyMode}, offlineOnlyMode: ${_this.offlineOnlyMode}, isScanning: ${_this.isScanning}, proxyEnabled: ${_this.proxyEnabled}, proxyType: ${_this.proxyType}, proxyHost: ${_this.proxyHost}, proxyPort: ${_this.proxyPort}, proxyUsername: ${_this.proxyUsername}, hasProxyPassword: ${_this.hasProxyPassword}, proxyBypassHosts: ${_this.proxyBypassHosts}, proxyList: ${_this.proxyList}, isTestingAllProxies: ${_this.isTestingAllProxies}, extractorEngine: ${_this.extractorEngine}, ytdlpBackendEnabled: ${_this.ytdlpBackendEnabled}, ytdlpBackendUrl: ${_this.ytdlpBackendUrl}, ytdlpBackendToken: ${_this.ytdlpBackendToken}, syncCookiesToBackend: ${_this.syncCookiesToBackend}, isTestingYtdlpBackend: ${_this.isTestingYtdlpBackend}, ytdlpBackendStatusMessage: ${_this.ytdlpBackendStatusMessage}, ytdlpBackendVersion: ${_this.ytdlpBackendVersion}, ytdlpBackendProxyCount: ${_this.ytdlpBackendProxyCount}, ytdlpBackendCircuitState: ${_this.ytdlpBackendCircuitState}, bitPerfectOutput: ${_this.bitPerfectOutput}, bypassDspOnBitPerfect: ${_this.bypassDspOnBitPerfect}, followTrackSampleRate: ${_this.followTrackSampleRate}, strictBitPerfect: ${_this.strictBitPerfect}, dsdOutputMode: ${_this.dsdOutputMode}, experienceMode: ${_this.experienceMode}, dsdDopSupported: ${_this.dsdDopSupported}, currentOutputDevice: ${_this.currentOutputDevice}, scanResultCount: ${_this.scanResultCount}, errorMessage: ${_this.errorMessage}, crossfeedEnabled: ${_this.crossfeedEnabled}, crossfeedDelayUs: ${_this.crossfeedDelayUs}, crossfeedFeedDb: ${_this.crossfeedFeedDb}, limiterEnabled: ${_this.limiterEnabled}, limiterLookaheadMs: ${_this.limiterLookaheadMs}, limiterThresholdDb: ${_this.limiterThresholdDb}, limiterReleaseMs: ${_this.limiterReleaseMs}, reverbEnabled: ${_this.reverbEnabled}, reverbPreset: ${_this.reverbPreset}, reverbWetDry: ${_this.reverbWetDry}, stereoBalance: ${_this.stereoBalance}, monoMix: ${_this.monoMix}, sincResamplerEnabled: ${_this.sincResamplerEnabled}, dspPreference: ${_this.dspPreference}, systemEffectsPolicy: ${_this.systemEffectsPolicy}, systemEffectsStatus: ${_this.systemEffectsStatus}, systemEffectsBundles: ${_this.systemEffectsBundles}, bluetoothLatencyOffsetMs: ${_this.bluetoothLatencyOffsetMs}, hedgedResolutionEnabled: ${_this.hedgedResolutionEnabled}, adaptiveQualityEnabled: ${_this.adaptiveQualityEnabled}, duckingMode: ${_this.duckingMode}, duckingLevel: ${_this.duckingLevel}, multiOutputMode: ${_this.multiOutputMode}, dspSnapshotEnabled: ${_this.dspSnapshotEnabled}, silenceSkipSensitivity: ${_this.silenceSkipSensitivity}, sessionLogEnabled: ${_this.sessionLogEnabled}, outputFormatNegotiationEnabled: ${_this.outputFormatNegotiationEnabled}, floatOutputEnabled: ${_this.floatOutputEnabled}, aaudioOutputEnabled: ${_this.aaudioOutputEnabled}, dvcEnabled: ${_this.dvcEnabled}, usbHardwareVolumeEnabled: ${_this.usbHardwareVolumeEnabled}, aaudioPreferExclusive: ${_this.aaudioPreferExclusive}, aaudioTargetBufferMs: ${_this.aaudioTargetBufferMs}, sincResamplerQuality: ${_this.sincResamplerQuality}, bpmSyncCrossfadeEnabled: ${_this.bpmSyncCrossfadeEnabled})';
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
      bool autoThemeByTime,
      bool highContrast,
      bool reduceMotion,
      double liquidGlassTint,
      String languageCode,
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
      bool hasProxyPassword,
      String proxyBypassHosts,
      List<ProxyEntry> proxyList,
      bool isTestingAllProxies,
      ExtractorEngine extractorEngine,
      bool ytdlpBackendEnabled,
      String ytdlpBackendUrl,
      String ytdlpBackendToken,
      bool syncCookiesToBackend,
      bool isTestingYtdlpBackend,
      String? ytdlpBackendStatusMessage,
      String? ytdlpBackendVersion,
      int? ytdlpBackendProxyCount,
      String? ytdlpBackendCircuitState,
      bool bitPerfectOutput,
      bool bypassDspOnBitPerfect,
      bool followTrackSampleRate,
      bool strictBitPerfect,
      DsdOutputMode dsdOutputMode,
      ExperienceMode experienceMode,
      bool dsdDopSupported,
      AudioOutputInfo? currentOutputDevice,
      int? scanResultCount,
      String? errorMessage,
      bool crossfeedEnabled,
      double crossfeedDelayUs,
      double crossfeedFeedDb,
      bool limiterEnabled,
      double limiterLookaheadMs,
      double limiterThresholdDb,
      double limiterReleaseMs,
      bool reverbEnabled,
      int reverbPreset,
      double reverbWetDry,
      double stereoBalance,
      bool monoMix,
      bool sincResamplerEnabled,
      String dspPreference,
      String systemEffectsPolicy,
      String systemEffectsStatus,
      List<String> systemEffectsBundles,
      int bluetoothLatencyOffsetMs,
      bool hedgedResolutionEnabled,
      bool adaptiveQualityEnabled,
      String duckingMode,
      double duckingLevel,
      String multiOutputMode,
      bool dspSnapshotEnabled,
      int silenceSkipSensitivity,
      bool sessionLogEnabled,
      bool outputFormatNegotiationEnabled,
      bool floatOutputEnabled,
      bool aaudioOutputEnabled,
      bool dvcEnabled,
      bool usbHardwareVolumeEnabled,
      bool aaudioPreferExclusive,
      int aaudioTargetBufferMs,
      int sincResamplerQuality,
      bool bpmSyncCrossfadeEnabled});
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
    Object? autoThemeByTime = null,
    Object? highContrast = null,
    Object? reduceMotion = null,
    Object? liquidGlassTint = null,
    Object? languageCode = null,
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
    Object? hasProxyPassword = null,
    Object? proxyBypassHosts = null,
    Object? proxyList = null,
    Object? isTestingAllProxies = null,
    Object? extractorEngine = null,
    Object? ytdlpBackendEnabled = null,
    Object? ytdlpBackendUrl = null,
    Object? ytdlpBackendToken = null,
    Object? syncCookiesToBackend = null,
    Object? isTestingYtdlpBackend = null,
    Object? ytdlpBackendStatusMessage = freezed,
    Object? ytdlpBackendVersion = freezed,
    Object? ytdlpBackendProxyCount = freezed,
    Object? ytdlpBackendCircuitState = freezed,
    Object? bitPerfectOutput = null,
    Object? bypassDspOnBitPerfect = null,
    Object? followTrackSampleRate = null,
    Object? strictBitPerfect = null,
    Object? dsdOutputMode = null,
    Object? experienceMode = null,
    Object? dsdDopSupported = null,
    Object? currentOutputDevice = freezed,
    Object? scanResultCount = freezed,
    Object? errorMessage = freezed,
    Object? crossfeedEnabled = null,
    Object? crossfeedDelayUs = null,
    Object? crossfeedFeedDb = null,
    Object? limiterEnabled = null,
    Object? limiterLookaheadMs = null,
    Object? limiterThresholdDb = null,
    Object? limiterReleaseMs = null,
    Object? reverbEnabled = null,
    Object? reverbPreset = null,
    Object? reverbWetDry = null,
    Object? stereoBalance = null,
    Object? monoMix = null,
    Object? sincResamplerEnabled = null,
    Object? dspPreference = null,
    Object? systemEffectsPolicy = null,
    Object? systemEffectsStatus = null,
    Object? systemEffectsBundles = null,
    Object? bluetoothLatencyOffsetMs = null,
    Object? hedgedResolutionEnabled = null,
    Object? adaptiveQualityEnabled = null,
    Object? duckingMode = null,
    Object? duckingLevel = null,
    Object? multiOutputMode = null,
    Object? dspSnapshotEnabled = null,
    Object? silenceSkipSensitivity = null,
    Object? sessionLogEnabled = null,
    Object? outputFormatNegotiationEnabled = null,
    Object? floatOutputEnabled = null,
    Object? aaudioOutputEnabled = null,
    Object? dvcEnabled = null,
    Object? usbHardwareVolumeEnabled = null,
    Object? aaudioPreferExclusive = null,
    Object? aaudioTargetBufferMs = null,
    Object? sincResamplerQuality = null,
    Object? bpmSyncCrossfadeEnabled = null,
  }) {
    return _then(SettingsState(
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
      autoThemeByTime: null == autoThemeByTime
          ? _self.autoThemeByTime
          : autoThemeByTime // ignore: cast_nullable_to_non_nullable
              as bool,
      highContrast: null == highContrast
          ? _self.highContrast
          : highContrast // ignore: cast_nullable_to_non_nullable
              as bool,
      reduceMotion: null == reduceMotion
          ? _self.reduceMotion
          : reduceMotion // ignore: cast_nullable_to_non_nullable
              as bool,
      liquidGlassTint: null == liquidGlassTint
          ? _self.liquidGlassTint
          : liquidGlassTint // ignore: cast_nullable_to_non_nullable
              as double,
      languageCode: null == languageCode
          ? _self.languageCode
          : languageCode // ignore: cast_nullable_to_non_nullable
              as String,
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
      hasProxyPassword: null == hasProxyPassword
          ? _self.hasProxyPassword
          : hasProxyPassword // ignore: cast_nullable_to_non_nullable
              as bool,
      proxyBypassHosts: null == proxyBypassHosts
          ? _self.proxyBypassHosts
          : proxyBypassHosts // ignore: cast_nullable_to_non_nullable
              as String,
      proxyList: null == proxyList
          ? _self.proxyList
          : proxyList // ignore: cast_nullable_to_non_nullable
              as List<ProxyEntry>,
      isTestingAllProxies: null == isTestingAllProxies
          ? _self.isTestingAllProxies
          : isTestingAllProxies // ignore: cast_nullable_to_non_nullable
              as bool,
      extractorEngine: null == extractorEngine
          ? _self.extractorEngine
          : extractorEngine // ignore: cast_nullable_to_non_nullable
              as ExtractorEngine,
      ytdlpBackendEnabled: null == ytdlpBackendEnabled
          ? _self.ytdlpBackendEnabled
          : ytdlpBackendEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      ytdlpBackendUrl: null == ytdlpBackendUrl
          ? _self.ytdlpBackendUrl
          : ytdlpBackendUrl // ignore: cast_nullable_to_non_nullable
              as String,
      ytdlpBackendToken: null == ytdlpBackendToken
          ? _self.ytdlpBackendToken
          : ytdlpBackendToken // ignore: cast_nullable_to_non_nullable
              as String,
      syncCookiesToBackend: null == syncCookiesToBackend
          ? _self.syncCookiesToBackend
          : syncCookiesToBackend // ignore: cast_nullable_to_non_nullable
              as bool,
      isTestingYtdlpBackend: null == isTestingYtdlpBackend
          ? _self.isTestingYtdlpBackend
          : isTestingYtdlpBackend // ignore: cast_nullable_to_non_nullable
              as bool,
      ytdlpBackendStatusMessage: freezed == ytdlpBackendStatusMessage
          ? _self.ytdlpBackendStatusMessage
          : ytdlpBackendStatusMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      ytdlpBackendVersion: freezed == ytdlpBackendVersion
          ? _self.ytdlpBackendVersion
          : ytdlpBackendVersion // ignore: cast_nullable_to_non_nullable
              as String?,
      ytdlpBackendProxyCount: freezed == ytdlpBackendProxyCount
          ? _self.ytdlpBackendProxyCount
          : ytdlpBackendProxyCount // ignore: cast_nullable_to_non_nullable
              as int?,
      ytdlpBackendCircuitState: freezed == ytdlpBackendCircuitState
          ? _self.ytdlpBackendCircuitState
          : ytdlpBackendCircuitState // ignore: cast_nullable_to_non_nullable
              as String?,
      bitPerfectOutput: null == bitPerfectOutput
          ? _self.bitPerfectOutput
          : bitPerfectOutput // ignore: cast_nullable_to_non_nullable
              as bool,
      bypassDspOnBitPerfect: null == bypassDspOnBitPerfect
          ? _self.bypassDspOnBitPerfect
          : bypassDspOnBitPerfect // ignore: cast_nullable_to_non_nullable
              as bool,
      followTrackSampleRate: null == followTrackSampleRate
          ? _self.followTrackSampleRate
          : followTrackSampleRate // ignore: cast_nullable_to_non_nullable
              as bool,
      strictBitPerfect: null == strictBitPerfect
          ? _self.strictBitPerfect
          : strictBitPerfect // ignore: cast_nullable_to_non_nullable
              as bool,
      dsdOutputMode: null == dsdOutputMode
          ? _self.dsdOutputMode
          : dsdOutputMode // ignore: cast_nullable_to_non_nullable
              as DsdOutputMode,
      experienceMode: null == experienceMode
          ? _self.experienceMode
          : experienceMode // ignore: cast_nullable_to_non_nullable
              as ExperienceMode,
      dsdDopSupported: null == dsdDopSupported
          ? _self.dsdDopSupported
          : dsdDopSupported // ignore: cast_nullable_to_non_nullable
              as bool,
      currentOutputDevice: freezed == currentOutputDevice
          ? _self.currentOutputDevice
          : currentOutputDevice // ignore: cast_nullable_to_non_nullable
              as AudioOutputInfo?,
      scanResultCount: freezed == scanResultCount
          ? _self.scanResultCount
          : scanResultCount // ignore: cast_nullable_to_non_nullable
              as int?,
      errorMessage: freezed == errorMessage
          ? _self.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      crossfeedEnabled: null == crossfeedEnabled
          ? _self.crossfeedEnabled
          : crossfeedEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      crossfeedDelayUs: null == crossfeedDelayUs
          ? _self.crossfeedDelayUs
          : crossfeedDelayUs // ignore: cast_nullable_to_non_nullable
              as double,
      crossfeedFeedDb: null == crossfeedFeedDb
          ? _self.crossfeedFeedDb
          : crossfeedFeedDb // ignore: cast_nullable_to_non_nullable
              as double,
      limiterEnabled: null == limiterEnabled
          ? _self.limiterEnabled
          : limiterEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      limiterLookaheadMs: null == limiterLookaheadMs
          ? _self.limiterLookaheadMs
          : limiterLookaheadMs // ignore: cast_nullable_to_non_nullable
              as double,
      limiterThresholdDb: null == limiterThresholdDb
          ? _self.limiterThresholdDb
          : limiterThresholdDb // ignore: cast_nullable_to_non_nullable
              as double,
      limiterReleaseMs: null == limiterReleaseMs
          ? _self.limiterReleaseMs
          : limiterReleaseMs // ignore: cast_nullable_to_non_nullable
              as double,
      reverbEnabled: null == reverbEnabled
          ? _self.reverbEnabled
          : reverbEnabled // ignore: cast_nullable_to_non_nullable
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
      sincResamplerEnabled: null == sincResamplerEnabled
          ? _self.sincResamplerEnabled
          : sincResamplerEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      dspPreference: null == dspPreference
          ? _self.dspPreference
          : dspPreference // ignore: cast_nullable_to_non_nullable
              as String,
      systemEffectsPolicy: null == systemEffectsPolicy
          ? _self.systemEffectsPolicy
          : systemEffectsPolicy // ignore: cast_nullable_to_non_nullable
              as String,
      systemEffectsStatus: null == systemEffectsStatus
          ? _self.systemEffectsStatus
          : systemEffectsStatus // ignore: cast_nullable_to_non_nullable
              as String,
      systemEffectsBundles: null == systemEffectsBundles
          ? _self.systemEffectsBundles
          : systemEffectsBundles // ignore: cast_nullable_to_non_nullable
              as List<String>,
      bluetoothLatencyOffsetMs: null == bluetoothLatencyOffsetMs
          ? _self.bluetoothLatencyOffsetMs
          : bluetoothLatencyOffsetMs // ignore: cast_nullable_to_non_nullable
              as int,
      hedgedResolutionEnabled: null == hedgedResolutionEnabled
          ? _self.hedgedResolutionEnabled
          : hedgedResolutionEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      adaptiveQualityEnabled: null == adaptiveQualityEnabled
          ? _self.adaptiveQualityEnabled
          : adaptiveQualityEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      duckingMode: null == duckingMode
          ? _self.duckingMode
          : duckingMode // ignore: cast_nullable_to_non_nullable
              as String,
      duckingLevel: null == duckingLevel
          ? _self.duckingLevel
          : duckingLevel // ignore: cast_nullable_to_non_nullable
              as double,
      multiOutputMode: null == multiOutputMode
          ? _self.multiOutputMode
          : multiOutputMode // ignore: cast_nullable_to_non_nullable
              as String,
      dspSnapshotEnabled: null == dspSnapshotEnabled
          ? _self.dspSnapshotEnabled
          : dspSnapshotEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      silenceSkipSensitivity: null == silenceSkipSensitivity
          ? _self.silenceSkipSensitivity
          : silenceSkipSensitivity // ignore: cast_nullable_to_non_nullable
              as int,
      sessionLogEnabled: null == sessionLogEnabled
          ? _self.sessionLogEnabled
          : sessionLogEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      outputFormatNegotiationEnabled: null == outputFormatNegotiationEnabled
          ? _self.outputFormatNegotiationEnabled
          : outputFormatNegotiationEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      floatOutputEnabled: null == floatOutputEnabled
          ? _self.floatOutputEnabled
          : floatOutputEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      aaudioOutputEnabled: null == aaudioOutputEnabled
          ? _self.aaudioOutputEnabled
          : aaudioOutputEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      dvcEnabled: null == dvcEnabled
          ? _self.dvcEnabled
          : dvcEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      usbHardwareVolumeEnabled: null == usbHardwareVolumeEnabled
          ? _self.usbHardwareVolumeEnabled
          : usbHardwareVolumeEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      aaudioPreferExclusive: null == aaudioPreferExclusive
          ? _self.aaudioPreferExclusive
          : aaudioPreferExclusive // ignore: cast_nullable_to_non_nullable
              as bool,
      aaudioTargetBufferMs: null == aaudioTargetBufferMs
          ? _self.aaudioTargetBufferMs
          : aaudioTargetBufferMs // ignore: cast_nullable_to_non_nullable
              as int,
      sincResamplerQuality: null == sincResamplerQuality
          ? _self.sincResamplerQuality
          : sincResamplerQuality // ignore: cast_nullable_to_non_nullable
              as int,
      bpmSyncCrossfadeEnabled: null == bpmSyncCrossfadeEnabled
          ? _self.bpmSyncCrossfadeEnabled
          : bpmSyncCrossfadeEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
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
            bool autoThemeByTime,
            bool highContrast,
            bool reduceMotion,
            double liquidGlassTint,
            String languageCode,
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
            bool hasProxyPassword,
            String proxyBypassHosts,
            List<ProxyEntry> proxyList,
            bool isTestingAllProxies,
            ExtractorEngine extractorEngine,
            bool ytdlpBackendEnabled,
            String ytdlpBackendUrl,
            String ytdlpBackendToken,
            bool syncCookiesToBackend,
            bool isTestingYtdlpBackend,
            String? ytdlpBackendStatusMessage,
            String? ytdlpBackendVersion,
            int? ytdlpBackendProxyCount,
            String? ytdlpBackendCircuitState,
            bool bitPerfectOutput,
            bool bypassDspOnBitPerfect,
            bool followTrackSampleRate,
            bool strictBitPerfect,
            DsdOutputMode dsdOutputMode,
            ExperienceMode experienceMode,
            bool dsdDopSupported,
            AudioOutputInfo? currentOutputDevice,
            int? scanResultCount,
            String? errorMessage,
            bool crossfeedEnabled,
            double crossfeedDelayUs,
            double crossfeedFeedDb,
            bool limiterEnabled,
            double limiterLookaheadMs,
            double limiterThresholdDb,
            double limiterReleaseMs,
            bool reverbEnabled,
            int reverbPreset,
            double reverbWetDry,
            double stereoBalance,
            bool monoMix,
            bool sincResamplerEnabled,
            String dspPreference,
            String systemEffectsPolicy,
            String systemEffectsStatus,
            List<String> systemEffectsBundles,
            int bluetoothLatencyOffsetMs,
            bool hedgedResolutionEnabled,
            bool adaptiveQualityEnabled,
            String duckingMode,
            double duckingLevel,
            String multiOutputMode,
            bool dspSnapshotEnabled,
            int silenceSkipSensitivity,
            bool sessionLogEnabled,
            bool outputFormatNegotiationEnabled,
            bool floatOutputEnabled,
            bool aaudioOutputEnabled,
            bool dvcEnabled,
            bool usbHardwareVolumeEnabled,
            bool aaudioPreferExclusive,
            int aaudioTargetBufferMs,
            int sincResamplerQuality,
            bool bpmSyncCrossfadeEnabled)?
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
            _that.autoThemeByTime,
            _that.highContrast,
            _that.reduceMotion,
            _that.liquidGlassTint,
            _that.languageCode,
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
            _that.hasProxyPassword,
            _that.proxyBypassHosts,
            _that.proxyList,
            _that.isTestingAllProxies,
            _that.extractorEngine,
            _that.ytdlpBackendEnabled,
            _that.ytdlpBackendUrl,
            _that.ytdlpBackendToken,
            _that.syncCookiesToBackend,
            _that.isTestingYtdlpBackend,
            _that.ytdlpBackendStatusMessage,
            _that.ytdlpBackendVersion,
            _that.ytdlpBackendProxyCount,
            _that.ytdlpBackendCircuitState,
            _that.bitPerfectOutput,
            _that.bypassDspOnBitPerfect,
            _that.followTrackSampleRate,
            _that.strictBitPerfect,
            _that.dsdOutputMode,
            _that.experienceMode,
            _that.dsdDopSupported,
            _that.currentOutputDevice,
            _that.scanResultCount,
            _that.errorMessage,
            _that.crossfeedEnabled,
            _that.crossfeedDelayUs,
            _that.crossfeedFeedDb,
            _that.limiterEnabled,
            _that.limiterLookaheadMs,
            _that.limiterThresholdDb,
            _that.limiterReleaseMs,
            _that.reverbEnabled,
            _that.reverbPreset,
            _that.reverbWetDry,
            _that.stereoBalance,
            _that.monoMix,
            _that.sincResamplerEnabled,
            _that.dspPreference,
            _that.systemEffectsPolicy,
            _that.systemEffectsStatus,
            _that.systemEffectsBundles,
            _that.bluetoothLatencyOffsetMs,
            _that.hedgedResolutionEnabled,
            _that.adaptiveQualityEnabled,
            _that.duckingMode,
            _that.duckingLevel,
            _that.multiOutputMode,
            _that.dspSnapshotEnabled,
            _that.silenceSkipSensitivity,
            _that.sessionLogEnabled,
            _that.outputFormatNegotiationEnabled,
            _that.floatOutputEnabled,
            _that.aaudioOutputEnabled,
            _that.dvcEnabled,
            _that.usbHardwareVolumeEnabled,
            _that.aaudioPreferExclusive,
            _that.aaudioTargetBufferMs,
            _that.sincResamplerQuality,
            _that.bpmSyncCrossfadeEnabled);
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
            bool autoThemeByTime,
            bool highContrast,
            bool reduceMotion,
            double liquidGlassTint,
            String languageCode,
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
            bool hasProxyPassword,
            String proxyBypassHosts,
            List<ProxyEntry> proxyList,
            bool isTestingAllProxies,
            ExtractorEngine extractorEngine,
            bool ytdlpBackendEnabled,
            String ytdlpBackendUrl,
            String ytdlpBackendToken,
            bool syncCookiesToBackend,
            bool isTestingYtdlpBackend,
            String? ytdlpBackendStatusMessage,
            String? ytdlpBackendVersion,
            int? ytdlpBackendProxyCount,
            String? ytdlpBackendCircuitState,
            bool bitPerfectOutput,
            bool bypassDspOnBitPerfect,
            bool followTrackSampleRate,
            bool strictBitPerfect,
            DsdOutputMode dsdOutputMode,
            ExperienceMode experienceMode,
            bool dsdDopSupported,
            AudioOutputInfo? currentOutputDevice,
            int? scanResultCount,
            String? errorMessage,
            bool crossfeedEnabled,
            double crossfeedDelayUs,
            double crossfeedFeedDb,
            bool limiterEnabled,
            double limiterLookaheadMs,
            double limiterThresholdDb,
            double limiterReleaseMs,
            bool reverbEnabled,
            int reverbPreset,
            double reverbWetDry,
            double stereoBalance,
            bool monoMix,
            bool sincResamplerEnabled,
            String dspPreference,
            String systemEffectsPolicy,
            String systemEffectsStatus,
            List<String> systemEffectsBundles,
            int bluetoothLatencyOffsetMs,
            bool hedgedResolutionEnabled,
            bool adaptiveQualityEnabled,
            String duckingMode,
            double duckingLevel,
            String multiOutputMode,
            bool dspSnapshotEnabled,
            int silenceSkipSensitivity,
            bool sessionLogEnabled,
            bool outputFormatNegotiationEnabled,
            bool floatOutputEnabled,
            bool aaudioOutputEnabled,
            bool dvcEnabled,
            bool usbHardwareVolumeEnabled,
            bool aaudioPreferExclusive,
            int aaudioTargetBufferMs,
            int sincResamplerQuality,
            bool bpmSyncCrossfadeEnabled)
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
            _that.autoThemeByTime,
            _that.highContrast,
            _that.reduceMotion,
            _that.liquidGlassTint,
            _that.languageCode,
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
            _that.hasProxyPassword,
            _that.proxyBypassHosts,
            _that.proxyList,
            _that.isTestingAllProxies,
            _that.extractorEngine,
            _that.ytdlpBackendEnabled,
            _that.ytdlpBackendUrl,
            _that.ytdlpBackendToken,
            _that.syncCookiesToBackend,
            _that.isTestingYtdlpBackend,
            _that.ytdlpBackendStatusMessage,
            _that.ytdlpBackendVersion,
            _that.ytdlpBackendProxyCount,
            _that.ytdlpBackendCircuitState,
            _that.bitPerfectOutput,
            _that.bypassDspOnBitPerfect,
            _that.followTrackSampleRate,
            _that.strictBitPerfect,
            _that.dsdOutputMode,
            _that.experienceMode,
            _that.dsdDopSupported,
            _that.currentOutputDevice,
            _that.scanResultCount,
            _that.errorMessage,
            _that.crossfeedEnabled,
            _that.crossfeedDelayUs,
            _that.crossfeedFeedDb,
            _that.limiterEnabled,
            _that.limiterLookaheadMs,
            _that.limiterThresholdDb,
            _that.limiterReleaseMs,
            _that.reverbEnabled,
            _that.reverbPreset,
            _that.reverbWetDry,
            _that.stereoBalance,
            _that.monoMix,
            _that.sincResamplerEnabled,
            _that.dspPreference,
            _that.systemEffectsPolicy,
            _that.systemEffectsStatus,
            _that.systemEffectsBundles,
            _that.bluetoothLatencyOffsetMs,
            _that.hedgedResolutionEnabled,
            _that.adaptiveQualityEnabled,
            _that.duckingMode,
            _that.duckingLevel,
            _that.multiOutputMode,
            _that.dspSnapshotEnabled,
            _that.silenceSkipSensitivity,
            _that.sessionLogEnabled,
            _that.outputFormatNegotiationEnabled,
            _that.floatOutputEnabled,
            _that.aaudioOutputEnabled,
            _that.dvcEnabled,
            _that.usbHardwareVolumeEnabled,
            _that.aaudioPreferExclusive,
            _that.aaudioTargetBufferMs,
            _that.sincResamplerQuality,
            _that.bpmSyncCrossfadeEnabled);
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
            bool autoThemeByTime,
            bool highContrast,
            bool reduceMotion,
            double liquidGlassTint,
            String languageCode,
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
            bool hasProxyPassword,
            String proxyBypassHosts,
            List<ProxyEntry> proxyList,
            bool isTestingAllProxies,
            ExtractorEngine extractorEngine,
            bool ytdlpBackendEnabled,
            String ytdlpBackendUrl,
            String ytdlpBackendToken,
            bool syncCookiesToBackend,
            bool isTestingYtdlpBackend,
            String? ytdlpBackendStatusMessage,
            String? ytdlpBackendVersion,
            int? ytdlpBackendProxyCount,
            String? ytdlpBackendCircuitState,
            bool bitPerfectOutput,
            bool bypassDspOnBitPerfect,
            bool followTrackSampleRate,
            bool strictBitPerfect,
            DsdOutputMode dsdOutputMode,
            ExperienceMode experienceMode,
            bool dsdDopSupported,
            AudioOutputInfo? currentOutputDevice,
            int? scanResultCount,
            String? errorMessage,
            bool crossfeedEnabled,
            double crossfeedDelayUs,
            double crossfeedFeedDb,
            bool limiterEnabled,
            double limiterLookaheadMs,
            double limiterThresholdDb,
            double limiterReleaseMs,
            bool reverbEnabled,
            int reverbPreset,
            double reverbWetDry,
            double stereoBalance,
            bool monoMix,
            bool sincResamplerEnabled,
            String dspPreference,
            String systemEffectsPolicy,
            String systemEffectsStatus,
            List<String> systemEffectsBundles,
            int bluetoothLatencyOffsetMs,
            bool hedgedResolutionEnabled,
            bool adaptiveQualityEnabled,
            String duckingMode,
            double duckingLevel,
            String multiOutputMode,
            bool dspSnapshotEnabled,
            int silenceSkipSensitivity,
            bool sessionLogEnabled,
            bool outputFormatNegotiationEnabled,
            bool floatOutputEnabled,
            bool aaudioOutputEnabled,
            bool dvcEnabled,
            bool usbHardwareVolumeEnabled,
            bool aaudioPreferExclusive,
            int aaudioTargetBufferMs,
            int sincResamplerQuality,
            bool bpmSyncCrossfadeEnabled)?
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
            _that.autoThemeByTime,
            _that.highContrast,
            _that.reduceMotion,
            _that.liquidGlassTint,
            _that.languageCode,
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
            _that.hasProxyPassword,
            _that.proxyBypassHosts,
            _that.proxyList,
            _that.isTestingAllProxies,
            _that.extractorEngine,
            _that.ytdlpBackendEnabled,
            _that.ytdlpBackendUrl,
            _that.ytdlpBackendToken,
            _that.syncCookiesToBackend,
            _that.isTestingYtdlpBackend,
            _that.ytdlpBackendStatusMessage,
            _that.ytdlpBackendVersion,
            _that.ytdlpBackendProxyCount,
            _that.ytdlpBackendCircuitState,
            _that.bitPerfectOutput,
            _that.bypassDspOnBitPerfect,
            _that.followTrackSampleRate,
            _that.strictBitPerfect,
            _that.dsdOutputMode,
            _that.experienceMode,
            _that.dsdDopSupported,
            _that.currentOutputDevice,
            _that.scanResultCount,
            _that.errorMessage,
            _that.crossfeedEnabled,
            _that.crossfeedDelayUs,
            _that.crossfeedFeedDb,
            _that.limiterEnabled,
            _that.limiterLookaheadMs,
            _that.limiterThresholdDb,
            _that.limiterReleaseMs,
            _that.reverbEnabled,
            _that.reverbPreset,
            _that.reverbWetDry,
            _that.stereoBalance,
            _that.monoMix,
            _that.sincResamplerEnabled,
            _that.dspPreference,
            _that.systemEffectsPolicy,
            _that.systemEffectsStatus,
            _that.systemEffectsBundles,
            _that.bluetoothLatencyOffsetMs,
            _that.hedgedResolutionEnabled,
            _that.adaptiveQualityEnabled,
            _that.duckingMode,
            _that.duckingLevel,
            _that.multiOutputMode,
            _that.dspSnapshotEnabled,
            _that.silenceSkipSensitivity,
            _that.sessionLogEnabled,
            _that.outputFormatNegotiationEnabled,
            _that.floatOutputEnabled,
            _that.aaudioOutputEnabled,
            _that.dvcEnabled,
            _that.usbHardwareVolumeEnabled,
            _that.aaudioPreferExclusive,
            _that.aaudioTargetBufferMs,
            _that.sincResamplerQuality,
            _that.bpmSyncCrossfadeEnabled);
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
      this.autoThemeByTime = false,
      this.highContrast = false,
      this.reduceMotion = false,
      this.liquidGlassTint = 0.80,
      this.languageCode = 'system',
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
      this.hasProxyPassword = false,
      this.proxyBypassHosts = 'localhost, 127.0.0.1',
      List<ProxyEntry> proxyList = const [],
      this.isTestingAllProxies = false,
      this.extractorEngine = ExtractorEngine.onDevice,
      this.ytdlpBackendEnabled = false,
      this.ytdlpBackendUrl =
          'https://xdm-backend-10763667121.europe-west1.run.app',
      this.ytdlpBackendToken = '',
      this.syncCookiesToBackend = false,
      this.isTestingYtdlpBackend = false,
      this.ytdlpBackendStatusMessage,
      this.ytdlpBackendVersion,
      this.ytdlpBackendProxyCount,
      this.ytdlpBackendCircuitState,
      this.bitPerfectOutput = false,
      this.bypassDspOnBitPerfect = true,
      this.followTrackSampleRate = false,
      this.strictBitPerfect = false,
      this.dsdOutputMode = DsdOutputMode.pcm,
      this.experienceMode = ExperienceMode.normal,
      this.dsdDopSupported = false,
      this.currentOutputDevice,
      this.scanResultCount,
      this.errorMessage,
      this.crossfeedEnabled = false,
      this.crossfeedDelayUs = 350.0,
      this.crossfeedFeedDb = -9.0,
      this.limiterEnabled = false,
      this.limiterLookaheadMs = 3.0,
      this.limiterThresholdDb = -0.2,
      this.limiterReleaseMs = 50.0,
      this.reverbEnabled = false,
      this.reverbPreset = 0,
      this.reverbWetDry = 0.20,
      this.stereoBalance = 0.0,
      this.monoMix = false,
      this.sincResamplerEnabled = true,
      this.dspPreference = 'native',
      this.systemEffectsPolicy = 'auto',
      this.systemEffectsStatus = 'unknown',
      List<String> systemEffectsBundles = const <String>[],
      this.bluetoothLatencyOffsetMs = 150,
      this.hedgedResolutionEnabled = true,
      this.adaptiveQualityEnabled = true,
      this.duckingMode = 'duck',
      this.duckingLevel = 0.3,
      this.multiOutputMode = 'systemDefault',
      this.dspSnapshotEnabled = true,
      this.silenceSkipSensitivity = 0,
      this.sessionLogEnabled = true,
      this.outputFormatNegotiationEnabled = true,
      this.floatOutputEnabled = true,
      this.aaudioOutputEnabled = false,
      this.dvcEnabled = false,
      this.usbHardwareVolumeEnabled = false,
      this.aaudioPreferExclusive = true,
      this.aaudioTargetBufferMs = 150,
      this.sincResamplerQuality = 3,
      this.bpmSyncCrossfadeEnabled = false})
      : _proxyList = proxyList,
        _systemEffectsBundles = systemEffectsBundles,
        super._();

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
  final bool autoThemeByTime;
  @override
  @JsonKey()
  final bool highContrast;
  @override
  @JsonKey()
  final bool reduceMotion;
  @override
  @JsonKey()
  final double liquidGlassTint;
  @override
  @JsonKey()
  final String languageCode;
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
  final bool hasProxyPassword;
  @override
  @JsonKey()
  final String proxyBypassHosts;
  final List<ProxyEntry> _proxyList;
  @override
  @JsonKey()
  List<ProxyEntry> get proxyList {
    if (_proxyList is EqualUnmodifiableListView) return _proxyList;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_proxyList);
  }

  @override
  @JsonKey()
  final bool isTestingAllProxies;
  @override
  @JsonKey()
  final ExtractorEngine extractorEngine;
  @override
  @JsonKey()
  final bool ytdlpBackendEnabled;
  @override
  @JsonKey()
  final String ytdlpBackendUrl;
  @override
  @JsonKey()
  final String ytdlpBackendToken;
  @override
  @JsonKey()
  final bool syncCookiesToBackend;
  @override
  @JsonKey()
  final bool isTestingYtdlpBackend;
  @override
  final String? ytdlpBackendStatusMessage;
  @override
  final String? ytdlpBackendVersion;
  @override
  final int? ytdlpBackendProxyCount;
  @override
  final String? ytdlpBackendCircuitState;
  @override
  @JsonKey()
  final bool bitPerfectOutput;
  @override
  @JsonKey()
  final bool bypassDspOnBitPerfect;
  @override
  @JsonKey()
  final bool followTrackSampleRate;
  @override
  @JsonKey()
  final bool strictBitPerfect;
  @override
  @JsonKey()
  final DsdOutputMode dsdOutputMode;
  @override
  @JsonKey()
  final ExperienceMode experienceMode;
  @override
  @JsonKey()
  final bool dsdDopSupported;
  @override
  final AudioOutputInfo? currentOutputDevice;
  @override
  final int? scanResultCount;
  @override
  final String? errorMessage;
  @override
  @JsonKey()
  final bool crossfeedEnabled;
  @override
  @JsonKey()
  final double crossfeedDelayUs;
  @override
  @JsonKey()
  final double crossfeedFeedDb;
  @override
  @JsonKey()
  final bool limiterEnabled;
  @override
  @JsonKey()
  final double limiterLookaheadMs;
  @override
  @JsonKey()
  final double limiterThresholdDb;
  @override
  @JsonKey()
  final double limiterReleaseMs;
  @override
  @JsonKey()
  final bool reverbEnabled;
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
  final bool sincResamplerEnabled;
  @override
  @JsonKey()
  final String dspPreference;
  @override
  @JsonKey()
  final String systemEffectsPolicy;
  @override
  @JsonKey()
  final String systemEffectsStatus;
  final List<String> _systemEffectsBundles;
  @override
  @JsonKey()
  List<String> get systemEffectsBundles {
    if (_systemEffectsBundles is EqualUnmodifiableListView)
      return _systemEffectsBundles;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_systemEffectsBundles);
  }

  @override
  @JsonKey()
  final int bluetoothLatencyOffsetMs;
  @override
  @JsonKey()
  final bool hedgedResolutionEnabled;
  @override
  @JsonKey()
  final bool adaptiveQualityEnabled;
  @override
  @JsonKey()
  final String duckingMode;
  @override
  @JsonKey()
  final double duckingLevel;
  @override
  @JsonKey()
  final String multiOutputMode;
  @override
  @JsonKey()
  final bool dspSnapshotEnabled;
  @override
  @JsonKey()
  final int silenceSkipSensitivity;
  @override
  @JsonKey()
  final bool sessionLogEnabled;
  @override
  @JsonKey()
  final bool outputFormatNegotiationEnabled;
  @override
  @JsonKey()
  final bool floatOutputEnabled;
  @override
  @JsonKey()
  final bool aaudioOutputEnabled;
  @override
  @JsonKey()
  final bool dvcEnabled;
  @override
  @JsonKey()
  final bool usbHardwareVolumeEnabled;
  @override
  @JsonKey()
  final bool aaudioPreferExclusive;
  @override
  @JsonKey()
  final int aaudioTargetBufferMs;
  @override
  @JsonKey()
  final int sincResamplerQuality;
  @override
  @JsonKey()
  final bool bpmSyncCrossfadeEnabled;

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
            (identical(other.autoThemeByTime, autoThemeByTime) ||
                other.autoThemeByTime == autoThemeByTime) &&
            (identical(other.highContrast, highContrast) ||
                other.highContrast == highContrast) &&
            (identical(other.reduceMotion, reduceMotion) ||
                other.reduceMotion == reduceMotion) &&
            (identical(other.liquidGlassTint, liquidGlassTint) ||
                other.liquidGlassTint == liquidGlassTint) &&
            (identical(other.languageCode, languageCode) ||
                other.languageCode == languageCode) &&
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
            (identical(other.hasProxyPassword, hasProxyPassword) || other.hasProxyPassword == hasProxyPassword) &&
            (identical(other.proxyBypassHosts, proxyBypassHosts) || other.proxyBypassHosts == proxyBypassHosts) &&
            const DeepCollectionEquality().equals(other.proxyList, _proxyList) &&
            (identical(other.isTestingAllProxies, isTestingAllProxies) || other.isTestingAllProxies == isTestingAllProxies) &&
            (identical(other.extractorEngine, extractorEngine) || other.extractorEngine == extractorEngine) &&
            (identical(other.ytdlpBackendEnabled, ytdlpBackendEnabled) || other.ytdlpBackendEnabled == ytdlpBackendEnabled) &&
            (identical(other.ytdlpBackendUrl, ytdlpBackendUrl) || other.ytdlpBackendUrl == ytdlpBackendUrl) &&
            (identical(other.ytdlpBackendToken, ytdlpBackendToken) || other.ytdlpBackendToken == ytdlpBackendToken) &&
            (identical(other.syncCookiesToBackend, syncCookiesToBackend) || other.syncCookiesToBackend == syncCookiesToBackend) &&
            (identical(other.isTestingYtdlpBackend, isTestingYtdlpBackend) || other.isTestingYtdlpBackend == isTestingYtdlpBackend) &&
            (identical(other.ytdlpBackendStatusMessage, ytdlpBackendStatusMessage) || other.ytdlpBackendStatusMessage == ytdlpBackendStatusMessage) &&
            (identical(other.ytdlpBackendVersion, ytdlpBackendVersion) || other.ytdlpBackendVersion == ytdlpBackendVersion) &&
            (identical(other.ytdlpBackendProxyCount, ytdlpBackendProxyCount) || other.ytdlpBackendProxyCount == ytdlpBackendProxyCount) &&
            (identical(other.ytdlpBackendCircuitState, ytdlpBackendCircuitState) || other.ytdlpBackendCircuitState == ytdlpBackendCircuitState) &&
            (identical(other.bitPerfectOutput, bitPerfectOutput) || other.bitPerfectOutput == bitPerfectOutput) &&
            (identical(other.bypassDspOnBitPerfect, bypassDspOnBitPerfect) || other.bypassDspOnBitPerfect == bypassDspOnBitPerfect) &&
            (identical(other.followTrackSampleRate, followTrackSampleRate) || other.followTrackSampleRate == followTrackSampleRate) &&
            (identical(other.strictBitPerfect, strictBitPerfect) || other.strictBitPerfect == strictBitPerfect) &&
            (identical(other.dsdOutputMode, dsdOutputMode) || other.dsdOutputMode == dsdOutputMode) &&
            (identical(other.experienceMode, experienceMode) || other.experienceMode == experienceMode) &&
            (identical(other.dsdDopSupported, dsdDopSupported) || other.dsdDopSupported == dsdDopSupported) &&
            (identical(other.currentOutputDevice, currentOutputDevice) || other.currentOutputDevice == currentOutputDevice) &&
            (identical(other.scanResultCount, scanResultCount) || other.scanResultCount == scanResultCount) &&
            (identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage) &&
            (identical(other.crossfeedEnabled, crossfeedEnabled) || other.crossfeedEnabled == crossfeedEnabled) &&
            (identical(other.crossfeedDelayUs, crossfeedDelayUs) || other.crossfeedDelayUs == crossfeedDelayUs) &&
            (identical(other.crossfeedFeedDb, crossfeedFeedDb) || other.crossfeedFeedDb == crossfeedFeedDb) &&
            (identical(other.limiterEnabled, limiterEnabled) || other.limiterEnabled == limiterEnabled) &&
            (identical(other.limiterLookaheadMs, limiterLookaheadMs) || other.limiterLookaheadMs == limiterLookaheadMs) &&
            (identical(other.limiterThresholdDb, limiterThresholdDb) || other.limiterThresholdDb == limiterThresholdDb) &&
            (identical(other.limiterReleaseMs, limiterReleaseMs) || other.limiterReleaseMs == limiterReleaseMs) &&
            (identical(other.reverbEnabled, reverbEnabled) || other.reverbEnabled == reverbEnabled) &&
            (identical(other.reverbPreset, reverbPreset) || other.reverbPreset == reverbPreset) &&
            (identical(other.reverbWetDry, reverbWetDry) || other.reverbWetDry == reverbWetDry) &&
            (identical(other.stereoBalance, stereoBalance) || other.stereoBalance == stereoBalance) &&
            (identical(other.monoMix, monoMix) || other.monoMix == monoMix) &&
            (identical(other.sincResamplerEnabled, sincResamplerEnabled) || other.sincResamplerEnabled == sincResamplerEnabled) &&
            (identical(other.dspPreference, dspPreference) || other.dspPreference == dspPreference) &&
            (identical(other.systemEffectsPolicy, systemEffectsPolicy) || other.systemEffectsPolicy == systemEffectsPolicy) &&
            (identical(other.systemEffectsStatus, systemEffectsStatus) || other.systemEffectsStatus == systemEffectsStatus) &&
            const DeepCollectionEquality().equals(other.systemEffectsBundles, _systemEffectsBundles) &&
            (identical(other.bluetoothLatencyOffsetMs, bluetoothLatencyOffsetMs) || other.bluetoothLatencyOffsetMs == bluetoothLatencyOffsetMs) &&
            (identical(other.hedgedResolutionEnabled, hedgedResolutionEnabled) || other.hedgedResolutionEnabled == hedgedResolutionEnabled) &&
            (identical(other.adaptiveQualityEnabled, adaptiveQualityEnabled) || other.adaptiveQualityEnabled == adaptiveQualityEnabled) &&
            (identical(other.duckingMode, duckingMode) || other.duckingMode == duckingMode) &&
            (identical(other.duckingLevel, duckingLevel) || other.duckingLevel == duckingLevel) &&
            (identical(other.multiOutputMode, multiOutputMode) || other.multiOutputMode == multiOutputMode) &&
            (identical(other.dspSnapshotEnabled, dspSnapshotEnabled) || other.dspSnapshotEnabled == dspSnapshotEnabled) &&
            (identical(other.silenceSkipSensitivity, silenceSkipSensitivity) || other.silenceSkipSensitivity == silenceSkipSensitivity) &&
            (identical(other.sessionLogEnabled, sessionLogEnabled) || other.sessionLogEnabled == sessionLogEnabled) &&
            (identical(other.outputFormatNegotiationEnabled, outputFormatNegotiationEnabled) || other.outputFormatNegotiationEnabled == outputFormatNegotiationEnabled) &&
            (identical(other.floatOutputEnabled, floatOutputEnabled) || other.floatOutputEnabled == floatOutputEnabled) &&
            (identical(other.aaudioOutputEnabled, aaudioOutputEnabled) || other.aaudioOutputEnabled == aaudioOutputEnabled) &&
            (identical(other.dvcEnabled, dvcEnabled) || other.dvcEnabled == dvcEnabled) &&
            (identical(other.usbHardwareVolumeEnabled, usbHardwareVolumeEnabled) || other.usbHardwareVolumeEnabled == usbHardwareVolumeEnabled) &&
            (identical(other.aaudioPreferExclusive, aaudioPreferExclusive) || other.aaudioPreferExclusive == aaudioPreferExclusive) &&
            (identical(other.aaudioTargetBufferMs, aaudioTargetBufferMs) || other.aaudioTargetBufferMs == aaudioTargetBufferMs) &&
            (identical(other.sincResamplerQuality, sincResamplerQuality) || other.sincResamplerQuality == sincResamplerQuality) &&
            (identical(other.bpmSyncCrossfadeEnabled, bpmSyncCrossfadeEnabled) || other.bpmSyncCrossfadeEnabled == bpmSyncCrossfadeEnabled));
  }

  @override
  int get hashCode {
    return Object.hashAll([
      runtimeType,
      gaplessPlayback,
      crossfadeSeconds,
      minDurationSec,
      autoHideSystemMedia,
      themeColorSource,
      resumeAfterInterruption,
      waveformSeekBarEnabled,
      themeMode,
      autoThemeByTime,
      highContrast,
      reduceMotion,
      liquidGlassTint,
      languageCode,
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
      hasProxyPassword,
      proxyBypassHosts,
      const DeepCollectionEquality().hash(_proxyList),
      isTestingAllProxies,
      extractorEngine,
      ytdlpBackendEnabled,
      ytdlpBackendUrl,
      ytdlpBackendToken,
      syncCookiesToBackend,
      isTestingYtdlpBackend,
      ytdlpBackendStatusMessage,
      ytdlpBackendVersion,
      ytdlpBackendProxyCount,
      ytdlpBackendCircuitState,
      bitPerfectOutput,
      bypassDspOnBitPerfect,
      followTrackSampleRate,
      strictBitPerfect,
      dsdOutputMode,
      experienceMode,
      dsdDopSupported,
      currentOutputDevice,
      scanResultCount,
      errorMessage,
      crossfeedEnabled,
      crossfeedDelayUs,
      crossfeedFeedDb,
      limiterEnabled,
      limiterLookaheadMs,
      limiterThresholdDb,
      limiterReleaseMs,
      reverbEnabled,
      reverbPreset,
      reverbWetDry,
      stereoBalance,
      monoMix,
      sincResamplerEnabled,
      dspPreference,
      systemEffectsPolicy,
      systemEffectsStatus,
      const DeepCollectionEquality().hash(_systemEffectsBundles),
      bluetoothLatencyOffsetMs,
      hedgedResolutionEnabled,
      adaptiveQualityEnabled,
      duckingMode,
      duckingLevel,
      multiOutputMode,
      dspSnapshotEnabled,
      silenceSkipSensitivity,
      sessionLogEnabled,
      outputFormatNegotiationEnabled,
      floatOutputEnabled,
      aaudioOutputEnabled,
      dvcEnabled,
      usbHardwareVolumeEnabled,
      aaudioPreferExclusive,
      aaudioTargetBufferMs,
      sincResamplerQuality,
      bpmSyncCrossfadeEnabled
    ]);
  }

  @override
  String toString() {
    return 'SettingsState(gaplessPlayback: $gaplessPlayback, crossfadeSeconds: $crossfadeSeconds, minDurationSec: $minDurationSec, autoHideSystemMedia: $autoHideSystemMedia, themeColorSource: $themeColorSource, resumeAfterInterruption: $resumeAfterInterruption, waveformSeekBarEnabled: $waveformSeekBarEnabled, themeMode: $themeMode, autoThemeByTime: $autoThemeByTime, highContrast: $highContrast, reduceMotion: $reduceMotion, liquidGlassTint: $liquidGlassTint, languageCode: $languageCode, customAccentColorValue: $customAccentColorValue, playerThemeMode: $playerThemeMode, visualizerStyle: $visualizerStyle, miniPlayerSwipeLeft: $miniPlayerSwipeLeft, miniPlayerSwipeRight: $miniPlayerSwipeRight, nowPlayingDoubleTap: $nowPlayingDoubleTap, nowPlayingArtworkSwipe: $nowPlayingArtworkSwipe, replayGainMode: $replayGainMode, replayGainPreampWithRg: $replayGainPreampWithRg, replayGainPreampWithoutRg: $replayGainPreampWithoutRg, streamingQuality: $streamingQuality, downloadQuality: $downloadQuality, wifiOnlyMode: $wifiOnlyMode, offlineOnlyMode: $offlineOnlyMode, isScanning: $isScanning, proxyEnabled: $proxyEnabled, proxyType: $proxyType, proxyHost: $proxyHost, proxyPort: $proxyPort, proxyUsername: $proxyUsername, hasProxyPassword: $hasProxyPassword, proxyBypassHosts: $proxyBypassHosts, proxyList: $proxyList, isTestingAllProxies: $isTestingAllProxies, extractorEngine: $extractorEngine, ytdlpBackendEnabled: $ytdlpBackendEnabled, ytdlpBackendUrl: $ytdlpBackendUrl, ytdlpBackendToken: $ytdlpBackendToken, syncCookiesToBackend: $syncCookiesToBackend, isTestingYtdlpBackend: $isTestingYtdlpBackend, ytdlpBackendStatusMessage: $ytdlpBackendStatusMessage, ytdlpBackendVersion: $ytdlpBackendVersion, ytdlpBackendProxyCount: $ytdlpBackendProxyCount, ytdlpBackendCircuitState: $ytdlpBackendCircuitState, bitPerfectOutput: $bitPerfectOutput, bypassDspOnBitPerfect: $bypassDspOnBitPerfect, followTrackSampleRate: $followTrackSampleRate, strictBitPerfect: $strictBitPerfect, dsdOutputMode: $dsdOutputMode, experienceMode: $experienceMode, dsdDopSupported: $dsdDopSupported, currentOutputDevice: $currentOutputDevice, scanResultCount: $scanResultCount, errorMessage: $errorMessage, crossfeedEnabled: $crossfeedEnabled, crossfeedDelayUs: $crossfeedDelayUs, crossfeedFeedDb: $crossfeedFeedDb, limiterEnabled: $limiterEnabled, limiterLookaheadMs: $limiterLookaheadMs, limiterThresholdDb: $limiterThresholdDb, limiterReleaseMs: $limiterReleaseMs, reverbEnabled: $reverbEnabled, reverbPreset: $reverbPreset, reverbWetDry: $reverbWetDry, stereoBalance: $stereoBalance, monoMix: $monoMix, sincResamplerEnabled: $sincResamplerEnabled, dspPreference: $dspPreference, systemEffectsPolicy: $systemEffectsPolicy, systemEffectsStatus: $systemEffectsStatus, systemEffectsBundles: $systemEffectsBundles, bluetoothLatencyOffsetMs: $bluetoothLatencyOffsetMs, hedgedResolutionEnabled: $hedgedResolutionEnabled, adaptiveQualityEnabled: $adaptiveQualityEnabled, duckingMode: $duckingMode, duckingLevel: $duckingLevel, multiOutputMode: $multiOutputMode, dspSnapshotEnabled: $dspSnapshotEnabled, silenceSkipSensitivity: $silenceSkipSensitivity, sessionLogEnabled: $sessionLogEnabled, outputFormatNegotiationEnabled: $outputFormatNegotiationEnabled, floatOutputEnabled: $floatOutputEnabled, aaudioOutputEnabled: $aaudioOutputEnabled, dvcEnabled: $dvcEnabled, usbHardwareVolumeEnabled: $usbHardwareVolumeEnabled, aaudioPreferExclusive: $aaudioPreferExclusive, aaudioTargetBufferMs: $aaudioTargetBufferMs, sincResamplerQuality: $sincResamplerQuality, bpmSyncCrossfadeEnabled: $bpmSyncCrossfadeEnabled)';
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
      bool autoThemeByTime,
      bool highContrast,
      bool reduceMotion,
      double liquidGlassTint,
      String languageCode,
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
      bool hasProxyPassword,
      String proxyBypassHosts,
      List<ProxyEntry> proxyList,
      bool isTestingAllProxies,
      ExtractorEngine extractorEngine,
      bool ytdlpBackendEnabled,
      String ytdlpBackendUrl,
      String ytdlpBackendToken,
      bool syncCookiesToBackend,
      bool isTestingYtdlpBackend,
      String? ytdlpBackendStatusMessage,
      String? ytdlpBackendVersion,
      int? ytdlpBackendProxyCount,
      String? ytdlpBackendCircuitState,
      bool bitPerfectOutput,
      bool bypassDspOnBitPerfect,
      bool followTrackSampleRate,
      bool strictBitPerfect,
      DsdOutputMode dsdOutputMode,
      ExperienceMode experienceMode,
      bool dsdDopSupported,
      AudioOutputInfo? currentOutputDevice,
      int? scanResultCount,
      String? errorMessage,
      bool crossfeedEnabled,
      double crossfeedDelayUs,
      double crossfeedFeedDb,
      bool limiterEnabled,
      double limiterLookaheadMs,
      double limiterThresholdDb,
      double limiterReleaseMs,
      bool reverbEnabled,
      int reverbPreset,
      double reverbWetDry,
      double stereoBalance,
      bool monoMix,
      bool sincResamplerEnabled,
      String dspPreference,
      String systemEffectsPolicy,
      String systemEffectsStatus,
      List<String> systemEffectsBundles,
      int bluetoothLatencyOffsetMs,
      bool hedgedResolutionEnabled,
      bool adaptiveQualityEnabled,
      String duckingMode,
      double duckingLevel,
      String multiOutputMode,
      bool dspSnapshotEnabled,
      int silenceSkipSensitivity,
      bool sessionLogEnabled,
      bool outputFormatNegotiationEnabled,
      bool floatOutputEnabled,
      bool aaudioOutputEnabled,
      bool dvcEnabled,
      bool usbHardwareVolumeEnabled,
      bool aaudioPreferExclusive,
      int aaudioTargetBufferMs,
      int sincResamplerQuality,
      bool bpmSyncCrossfadeEnabled});
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
    Object? autoThemeByTime = null,
    Object? highContrast = null,
    Object? reduceMotion = null,
    Object? liquidGlassTint = null,
    Object? languageCode = null,
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
    Object? hasProxyPassword = null,
    Object? proxyBypassHosts = null,
    Object? proxyList = null,
    Object? isTestingAllProxies = null,
    Object? extractorEngine = null,
    Object? ytdlpBackendEnabled = null,
    Object? ytdlpBackendUrl = null,
    Object? ytdlpBackendToken = null,
    Object? syncCookiesToBackend = null,
    Object? isTestingYtdlpBackend = null,
    Object? ytdlpBackendStatusMessage = freezed,
    Object? ytdlpBackendVersion = freezed,
    Object? ytdlpBackendProxyCount = freezed,
    Object? ytdlpBackendCircuitState = freezed,
    Object? bitPerfectOutput = null,
    Object? bypassDspOnBitPerfect = null,
    Object? followTrackSampleRate = null,
    Object? strictBitPerfect = null,
    Object? dsdOutputMode = null,
    Object? experienceMode = null,
    Object? dsdDopSupported = null,
    Object? currentOutputDevice = freezed,
    Object? scanResultCount = freezed,
    Object? errorMessage = freezed,
    Object? crossfeedEnabled = null,
    Object? crossfeedDelayUs = null,
    Object? crossfeedFeedDb = null,
    Object? limiterEnabled = null,
    Object? limiterLookaheadMs = null,
    Object? limiterThresholdDb = null,
    Object? limiterReleaseMs = null,
    Object? reverbEnabled = null,
    Object? reverbPreset = null,
    Object? reverbWetDry = null,
    Object? stereoBalance = null,
    Object? monoMix = null,
    Object? sincResamplerEnabled = null,
    Object? dspPreference = null,
    Object? systemEffectsPolicy = null,
    Object? systemEffectsStatus = null,
    Object? systemEffectsBundles = null,
    Object? bluetoothLatencyOffsetMs = null,
    Object? hedgedResolutionEnabled = null,
    Object? adaptiveQualityEnabled = null,
    Object? duckingMode = null,
    Object? duckingLevel = null,
    Object? multiOutputMode = null,
    Object? dspSnapshotEnabled = null,
    Object? silenceSkipSensitivity = null,
    Object? sessionLogEnabled = null,
    Object? outputFormatNegotiationEnabled = null,
    Object? floatOutputEnabled = null,
    Object? aaudioOutputEnabled = null,
    Object? dvcEnabled = null,
    Object? usbHardwareVolumeEnabled = null,
    Object? aaudioPreferExclusive = null,
    Object? aaudioTargetBufferMs = null,
    Object? sincResamplerQuality = null,
    Object? bpmSyncCrossfadeEnabled = null,
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
      autoThemeByTime: null == autoThemeByTime
          ? _self.autoThemeByTime
          : autoThemeByTime // ignore: cast_nullable_to_non_nullable
              as bool,
      highContrast: null == highContrast
          ? _self.highContrast
          : highContrast // ignore: cast_nullable_to_non_nullable
              as bool,
      reduceMotion: null == reduceMotion
          ? _self.reduceMotion
          : reduceMotion // ignore: cast_nullable_to_non_nullable
              as bool,
      liquidGlassTint: null == liquidGlassTint
          ? _self.liquidGlassTint
          : liquidGlassTint // ignore: cast_nullable_to_non_nullable
              as double,
      languageCode: null == languageCode
          ? _self.languageCode
          : languageCode // ignore: cast_nullable_to_non_nullable
              as String,
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
      hasProxyPassword: null == hasProxyPassword
          ? _self.hasProxyPassword
          : hasProxyPassword // ignore: cast_nullable_to_non_nullable
              as bool,
      proxyBypassHosts: null == proxyBypassHosts
          ? _self.proxyBypassHosts
          : proxyBypassHosts // ignore: cast_nullable_to_non_nullable
              as String,
      proxyList: null == proxyList
          ? _self._proxyList
          : proxyList // ignore: cast_nullable_to_non_nullable
              as List<ProxyEntry>,
      isTestingAllProxies: null == isTestingAllProxies
          ? _self.isTestingAllProxies
          : isTestingAllProxies // ignore: cast_nullable_to_non_nullable
              as bool,
      extractorEngine: null == extractorEngine
          ? _self.extractorEngine
          : extractorEngine // ignore: cast_nullable_to_non_nullable
              as ExtractorEngine,
      ytdlpBackendEnabled: null == ytdlpBackendEnabled
          ? _self.ytdlpBackendEnabled
          : ytdlpBackendEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      ytdlpBackendUrl: null == ytdlpBackendUrl
          ? _self.ytdlpBackendUrl
          : ytdlpBackendUrl // ignore: cast_nullable_to_non_nullable
              as String,
      ytdlpBackendToken: null == ytdlpBackendToken
          ? _self.ytdlpBackendToken
          : ytdlpBackendToken // ignore: cast_nullable_to_non_nullable
              as String,
      syncCookiesToBackend: null == syncCookiesToBackend
          ? _self.syncCookiesToBackend
          : syncCookiesToBackend // ignore: cast_nullable_to_non_nullable
              as bool,
      isTestingYtdlpBackend: null == isTestingYtdlpBackend
          ? _self.isTestingYtdlpBackend
          : isTestingYtdlpBackend // ignore: cast_nullable_to_non_nullable
              as bool,
      ytdlpBackendStatusMessage: freezed == ytdlpBackendStatusMessage
          ? _self.ytdlpBackendStatusMessage
          : ytdlpBackendStatusMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      ytdlpBackendVersion: freezed == ytdlpBackendVersion
          ? _self.ytdlpBackendVersion
          : ytdlpBackendVersion // ignore: cast_nullable_to_non_nullable
              as String?,
      ytdlpBackendProxyCount: freezed == ytdlpBackendProxyCount
          ? _self.ytdlpBackendProxyCount
          : ytdlpBackendProxyCount // ignore: cast_nullable_to_non_nullable
              as int?,
      ytdlpBackendCircuitState: freezed == ytdlpBackendCircuitState
          ? _self.ytdlpBackendCircuitState
          : ytdlpBackendCircuitState // ignore: cast_nullable_to_non_nullable
              as String?,
      bitPerfectOutput: null == bitPerfectOutput
          ? _self.bitPerfectOutput
          : bitPerfectOutput // ignore: cast_nullable_to_non_nullable
              as bool,
      bypassDspOnBitPerfect: null == bypassDspOnBitPerfect
          ? _self.bypassDspOnBitPerfect
          : bypassDspOnBitPerfect // ignore: cast_nullable_to_non_nullable
              as bool,
      followTrackSampleRate: null == followTrackSampleRate
          ? _self.followTrackSampleRate
          : followTrackSampleRate // ignore: cast_nullable_to_non_nullable
              as bool,
      strictBitPerfect: null == strictBitPerfect
          ? _self.strictBitPerfect
          : strictBitPerfect // ignore: cast_nullable_to_non_nullable
              as bool,
      dsdOutputMode: null == dsdOutputMode
          ? _self.dsdOutputMode
          : dsdOutputMode // ignore: cast_nullable_to_non_nullable
              as DsdOutputMode,
      experienceMode: null == experienceMode
          ? _self.experienceMode
          : experienceMode // ignore: cast_nullable_to_non_nullable
              as ExperienceMode,
      dsdDopSupported: null == dsdDopSupported
          ? _self.dsdDopSupported
          : dsdDopSupported // ignore: cast_nullable_to_non_nullable
              as bool,
      currentOutputDevice: freezed == currentOutputDevice
          ? _self.currentOutputDevice
          : currentOutputDevice // ignore: cast_nullable_to_non_nullable
              as AudioOutputInfo?,
      scanResultCount: freezed == scanResultCount
          ? _self.scanResultCount
          : scanResultCount // ignore: cast_nullable_to_non_nullable
              as int?,
      errorMessage: freezed == errorMessage
          ? _self.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      crossfeedEnabled: null == crossfeedEnabled
          ? _self.crossfeedEnabled
          : crossfeedEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      crossfeedDelayUs: null == crossfeedDelayUs
          ? _self.crossfeedDelayUs
          : crossfeedDelayUs // ignore: cast_nullable_to_non_nullable
              as double,
      crossfeedFeedDb: null == crossfeedFeedDb
          ? _self.crossfeedFeedDb
          : crossfeedFeedDb // ignore: cast_nullable_to_non_nullable
              as double,
      limiterEnabled: null == limiterEnabled
          ? _self.limiterEnabled
          : limiterEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      limiterLookaheadMs: null == limiterLookaheadMs
          ? _self.limiterLookaheadMs
          : limiterLookaheadMs // ignore: cast_nullable_to_non_nullable
              as double,
      limiterThresholdDb: null == limiterThresholdDb
          ? _self.limiterThresholdDb
          : limiterThresholdDb // ignore: cast_nullable_to_non_nullable
              as double,
      limiterReleaseMs: null == limiterReleaseMs
          ? _self.limiterReleaseMs
          : limiterReleaseMs // ignore: cast_nullable_to_non_nullable
              as double,
      reverbEnabled: null == reverbEnabled
          ? _self.reverbEnabled
          : reverbEnabled // ignore: cast_nullable_to_non_nullable
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
      sincResamplerEnabled: null == sincResamplerEnabled
          ? _self.sincResamplerEnabled
          : sincResamplerEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      dspPreference: null == dspPreference
          ? _self.dspPreference
          : dspPreference // ignore: cast_nullable_to_non_nullable
              as String,
      systemEffectsPolicy: null == systemEffectsPolicy
          ? _self.systemEffectsPolicy
          : systemEffectsPolicy // ignore: cast_nullable_to_non_nullable
              as String,
      systemEffectsStatus: null == systemEffectsStatus
          ? _self.systemEffectsStatus
          : systemEffectsStatus // ignore: cast_nullable_to_non_nullable
              as String,
      systemEffectsBundles: null == systemEffectsBundles
          ? _self._systemEffectsBundles
          : systemEffectsBundles // ignore: cast_nullable_to_non_nullable
              as List<String>,
      bluetoothLatencyOffsetMs: null == bluetoothLatencyOffsetMs
          ? _self.bluetoothLatencyOffsetMs
          : bluetoothLatencyOffsetMs // ignore: cast_nullable_to_non_nullable
              as int,
      hedgedResolutionEnabled: null == hedgedResolutionEnabled
          ? _self.hedgedResolutionEnabled
          : hedgedResolutionEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      adaptiveQualityEnabled: null == adaptiveQualityEnabled
          ? _self.adaptiveQualityEnabled
          : adaptiveQualityEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      duckingMode: null == duckingMode
          ? _self.duckingMode
          : duckingMode // ignore: cast_nullable_to_non_nullable
              as String,
      duckingLevel: null == duckingLevel
          ? _self.duckingLevel
          : duckingLevel // ignore: cast_nullable_to_non_nullable
              as double,
      multiOutputMode: null == multiOutputMode
          ? _self.multiOutputMode
          : multiOutputMode // ignore: cast_nullable_to_non_nullable
              as String,
      dspSnapshotEnabled: null == dspSnapshotEnabled
          ? _self.dspSnapshotEnabled
          : dspSnapshotEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      silenceSkipSensitivity: null == silenceSkipSensitivity
          ? _self.silenceSkipSensitivity
          : silenceSkipSensitivity // ignore: cast_nullable_to_non_nullable
              as int,
      sessionLogEnabled: null == sessionLogEnabled
          ? _self.sessionLogEnabled
          : sessionLogEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      outputFormatNegotiationEnabled: null == outputFormatNegotiationEnabled
          ? _self.outputFormatNegotiationEnabled
          : outputFormatNegotiationEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      floatOutputEnabled: null == floatOutputEnabled
          ? _self.floatOutputEnabled
          : floatOutputEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      aaudioOutputEnabled: null == aaudioOutputEnabled
          ? _self.aaudioOutputEnabled
          : aaudioOutputEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      dvcEnabled: null == dvcEnabled
          ? _self.dvcEnabled
          : dvcEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      usbHardwareVolumeEnabled: null == usbHardwareVolumeEnabled
          ? _self.usbHardwareVolumeEnabled
          : usbHardwareVolumeEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      aaudioPreferExclusive: null == aaudioPreferExclusive
          ? _self.aaudioPreferExclusive
          : aaudioPreferExclusive // ignore: cast_nullable_to_non_nullable
              as bool,
      aaudioTargetBufferMs: null == aaudioTargetBufferMs
          ? _self.aaudioTargetBufferMs
          : aaudioTargetBufferMs // ignore: cast_nullable_to_non_nullable
              as int,
      sincResamplerQuality: null == sincResamplerQuality
          ? _self.sincResamplerQuality
          : sincResamplerQuality // ignore: cast_nullable_to_non_nullable
              as int,
      bpmSyncCrossfadeEnabled: null == bpmSyncCrossfadeEnabled
          ? _self.bpmSyncCrossfadeEnabled
          : bpmSyncCrossfadeEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

// dart format on
