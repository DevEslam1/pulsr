import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/bloc/base_cubit.dart';
import '../../../core/constants/channels.dart';
import '../../../core/constants/prefs_keys.dart';
import '../../../core/di/injection.dart';
import '../../../core/network/app_http_overrides.dart';
import '../../../core/network/proxy_config.dart';
import '../../../core/services/hires_audio_service.dart';
import '../../../core/services/theme_scheduler_service.dart';
import '../../../core/utils/error_logger.dart';
import '../../../data/audio/audio_effects_channel.dart';
import '../../../data/audio/audio_handler.dart';
import '../../../data/audio/dsd_decoder_helper.dart';
import '../../../data/audio/equalizer_manager.dart';
import '../../../data/scanner/media_scanner_service.dart';
import '../../../domain/repositories/music_repository_interface.dart';
import '../../../core/constants/audio_feature_info.dart';
import '../../player/presentation/widgets/audio_visualizer.dart';
import 'settings_state.dart';

@singleton
class SettingsCubit extends PulsrCubit<SettingsState> {
  final MediaScannerService _scannerService;
  final HiResAudioService _hiResAudioService;
  static const MethodChannel _proxyChannel = MethodChannel(PulsrChannels.proxy);

  static const String _keyGapless = 'setting_gapless';
  static const String _keyCrossfade = 'setting_crossfade';
  static const String _keyMinDuration = 'setting_min_duration';
  static const String _keyMinFileSizeKb = 'setting_min_file_size_kb';
  static const String _keyAutoHideSystemMedia =
      'setting_auto_hide_system_media';
  static const String _keyDynamicTheme = 'setting_dynamic_theme';
  static const String _keyThemeColorSource = 'setting_theme_color_source';
  static const String _keyResumeAfterInterruption =
      'setting_resume_after_interruption';
  static const String _keyWaveformSeekBar = 'setting_waveform_seek_bar';
  static const String _keyThemeMode = 'setting_theme_mode';
  static const String _keyAutoThemeByTime = 'setting_auto_theme_by_time';
  static const String _keyHighContrast = 'setting_high_contrast';
  static const String _keyLanguageCode = PrefsKeys.languageCode;
  static const String _keyCustomAccent = 'setting_custom_accent';
  static const String _keyPlayerThemeMode = 'setting_player_theme_mode';
  static const String _keyVisualizerStyle = 'setting_visualizer_style';
  static const String _keyMiniPlayerSwipeLeft =
      'setting_mini_player_swipe_left';
  static const String _keyMiniPlayerSwipeRight =
      'setting_mini_player_swipe_right';
  static const String _keyNowPlayingDoubleTap =
      'setting_now_playing_double_tap';
  static const String _keyNowPlayingArtworkSwipe =
      'setting_now_playing_artwork_swipe';
  static const String _keyReplayGainMode = 'setting_replay_gain_mode';
  static const String _keyReplayGainPreampWithRg =
      'setting_replay_gain_preamp_with_rg';
  static const String _keyReplayGainPreampWithoutRg =
      'setting_replay_gain_preamp_without_rg';
  static const String _keyStreamingQuality = 'setting_streaming_quality';
  static const String _keyDownloadQuality = 'setting_download_quality';
  static const String _keyWifiOnlyMode = 'setting_wifi_only_mode';
  static const String _keyOfflineOnlyMode = 'setting_offline_only_mode';
  static const String _keyDspPreference = 'setting_dsp_preference';

  // Proxy Keys
  static const String _keyProxyEnabled = 'setting_proxy_enabled';
  static const String _keyProxyType = 'setting_proxy_type';
  static const String _keyProxyHost = 'setting_proxy_host';
  static const String _keyProxyPort = 'setting_proxy_port';
  static const String _keyProxyUsername = 'setting_proxy_username';
  static const String _keyProxyPassword = 'setting_proxy_password';
  static const String _keyProxyPasswordSecure = 'proxy_password_secure';
  static const String _keyProxyBypassHosts = 'setting_proxy_bypass_hosts';
  static const String _keyProxyList = 'setting_proxy_list';
  static const String _keyProxyListPasswordsSecure =
      'proxy_pool_passwords_secure';

  final FlutterSecureStorage _secureStorage;
  ThemeSchedulerService? _themeScheduler;
  String _proxyPassword = '';

  /// Set by the proxy setters, cleared when a load starts. Lets a load that is
  /// still in flight know its on-disk snapshot is stale and must not clobber
  /// the edit the user just made.
  bool _proxyDirty = false;

  ProxyConfig get activeProxyConfig =>
      state.proxyConfig.copyWith(password: _proxyPassword);

  Stream<double> get scanProgress => _scannerService.scanProgress;

  Future<String> getProxyPassword() async {
    if (_proxyPassword.isNotEmpty) return _proxyPassword;
    try {
      final pass = await _secureStorage.read(key: _keyProxyPasswordSecure);
      if (pass != null) {
        _proxyPassword = pass;
      }
    } catch (_) {}
    return _proxyPassword;
  }

  SettingsCubit({
    required MediaScannerService scannerService,
    HiResAudioService? hiResAudioService,
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
  })  : _scannerService = scannerService,
        _secureStorage = secureStorage,
        _hiResAudioService = hiResAudioService ??
            (getIt.isRegistered<HiResAudioService>()
                ? getIt<HiResAudioService>()
                : HiResAudioService()),
        super(const SettingsState()) {
    autoSub(_hiResAudioService.outputDeviceStream, (device) {
      if (isClosed) return;
      final savedSampleRate = state.currentOutputDevice?.targetSampleRate ?? 0;
      final savedBitDepth = state.currentOutputDevice?.targetBitDepth ?? 0;
      safeEmit(
        state.copyWith(
          currentOutputDevice: device.copyWith(
            targetSampleRate: device.targetSampleRate != 0
                ? device.targetSampleRate
                : savedSampleRate,
            targetBitDepth: device.targetBitDepth != 0
                ? device.targetBitDepth
                : savedBitDepth,
          ),
        ),
      );
      // A DAC may have just been plugged/unplugged: re-probe DoP support so the
      // DSD output control enables/disables truthfully without a manual refresh.
      unawaited(_refreshDopSupport());
    });
    _initThemeScheduler();
    _loadPreferences();
  }

  /// Resolves the scheduler and consumes its stream. The callback is gated on
  /// [SettingsState.autoThemeByTime] so it never overrides a manual theme mode
  /// unless the user has opted into scheduled switching.
  void _initThemeScheduler() {
    try {
      _themeScheduler = getIt.isRegistered<ThemeSchedulerService>()
          ? getIt<ThemeSchedulerService>()
          : ThemeSchedulerService();
      autoSub(_themeScheduler!.isNightStream, _onNightChanged);
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to start theme scheduler',
        error: e,
        stackTrace: st,
        category: 'SettingsCubit',
      );
    }
  }

  void _onNightChanged(bool isNight) {
    if (isClosed || !state.autoThemeByTime) return;
    setThemeMode(isNight ? AppThemeMode.dark : AppThemeMode.light);
  }

  /// Starts the periodic schedule check. Only ever called when the preference
  /// is on, so installs that never opt in carry no timer.
  void _startThemeScheduler() {
    try {
      if (isClosed || !state.autoThemeByTime) return;
      _themeScheduler?.startScheduler((_) {});
    } catch (_) {}
  }

  @override
  Future<void> close() {
    _themeScheduler?.stopScheduler();
    return super.close();
  }

  void clearError() {
    safeEmit(state.copyWith(errorMessage: null));
  }

  Future<void> reloadSettings() async {
    await _loadPreferences();
  }

  Future<void> _syncProxySettings(ProxyConfig config) async {
    // 1. Synchronize Dart HttpOverrides
    AppHttpOverrides.instance.update(config);

    // 2. Synchronize Android Native / NewPipe / JVM Proxy
    // FIX-E03: Add platform check to prevent MissingPluginException on desktop
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _proxyChannel.invokeMethod('setProxy', config.toMap());
    } catch (e) {
      debugPrint('[SettingsCubit] Failed to sync proxy to native channel: $e');
    }
  }

  /// Reads the entry-ID-keyed proxy pool credentials out of secure storage.
  Future<Map<String, String>> _readProxyPoolSecrets() async {
    final secrets = <String, String>{};
    final raw = await _safeSecureRead(_keyProxyListPasswordsSecure);
    if (raw == null || raw.isEmpty) return secrets;
    try {
      (jsonDecode(raw) as Map<String, dynamic>).forEach((id, value) {
        if (value is String && value.isNotEmpty) secrets[id] = value;
      });
    } catch (_) {}
    return secrets;
  }

  Future<String?> _safeSecureRead(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to read secure storage key: $key',
        error: e,
        stackTrace: st,
        category: 'SettingsCubit',
      );
      return null;
    }
  }

  Future<void> _loadPreferences() async {
    _proxyDirty = false;
    try {
      final results = await Future.wait([
        SharedPreferences.getInstance(),
        _safeSecureRead(_keyProxyPasswordSecure),
        _safeSecureRead('xdm_backend_token_secure'),
      ]);
      final prefs = results[0] as SharedPreferences;
      String proxyPassword = (results[1] as String?) ?? '';

      // Remote backend decommissioned: drop any stored backend token.

      // Migration verification for proxy password
      if (prefs.containsKey(_keyProxyPassword) && proxyPassword.isEmpty) {
        final legacyPass = prefs.getString(_keyProxyPassword) ?? '';
        if (legacyPass.isNotEmpty) {
          try {
            await _secureStorage.write(
              key: _keyProxyPasswordSecure,
              value: legacyPass,
            );
            final verify = await _secureStorage.read(
              key: _keyProxyPasswordSecure,
            );
            if (verify == legacyPass) {
              await prefs.remove(_keyProxyPassword);
              proxyPassword = legacyPass;
            } else {
              ErrorLogger.log(
                'Secure storage migration mismatch for proxy password',
                category: 'SettingsCubit',
              );
              proxyPassword = legacyPass;
            }
          } catch (e) {
            proxyPassword = legacyPass;
          }
        }
      }

      final themeModeStr =
          prefs.getString(_keyThemeMode) ?? AppThemeMode.dark.name;
      final themeMode = AppThemeMode.values.firstWhere(
        (e) => e.name == themeModeStr,
        orElse: () => AppThemeMode.dark,
      );
      final customAccentValue = prefs.getInt(_keyCustomAccent) ?? 0xFF9B9EF5;

      final playerThemeStr =
          prefs.getString(_keyPlayerThemeMode) ?? PlayerThemeMode.classic.name;
      final playerThemeMode = PlayerThemeMode.values.firstWhere(
        (e) => e.name == playerThemeStr,
        orElse: () => PlayerThemeMode.classic,
      );

      final visualizerStyleStr =
          prefs.getString(_keyVisualizerStyle) ?? VisualizerStyle.bar.name;
      final visualizerStyle = VisualizerStyle.values.firstWhere(
        (e) => e.name == visualizerStyleStr,
        orElse: () => VisualizerStyle.bar,
      );

      final miniPlayerSwipeLeftStr = prefs.getString(_keyMiniPlayerSwipeLeft) ??
          MiniPlayerSwipeAction.next.name;
      final miniPlayerSwipeLeft = MiniPlayerSwipeAction.values.firstWhere(
        (e) => e.name == miniPlayerSwipeLeftStr,
        orElse: () => MiniPlayerSwipeAction.next,
      );

      final miniPlayerSwipeRightStr =
          prefs.getString(_keyMiniPlayerSwipeRight) ??
              MiniPlayerSwipeAction.prev.name;
      final miniPlayerSwipeRight = MiniPlayerSwipeAction.values.firstWhere(
        (e) => e.name == miniPlayerSwipeRightStr,
        orElse: () => MiniPlayerSwipeAction.prev,
      );

      final nowPlayingDoubleTapStr = prefs.getString(_keyNowPlayingDoubleTap) ??
          NowPlayingDoubleTapAction.toggleFavorite.name;
      final nowPlayingDoubleTap = NowPlayingDoubleTapAction.values.firstWhere(
        (e) => e.name == nowPlayingDoubleTapStr,
        orElse: () => NowPlayingDoubleTapAction.toggleFavorite,
      );

      final nowPlayingArtworkSwipeStr =
          prefs.getString(_keyNowPlayingArtworkSwipe) ??
              NowPlayingArtworkSwipeAction.nextPrev.name;
      final nowPlayingArtworkSwipe =
          NowPlayingArtworkSwipeAction.values.firstWhere(
        (e) => e.name == nowPlayingArtworkSwipeStr,
        orElse: () => NowPlayingArtworkSwipeAction.nextPrev,
      );

      final replayGainModeStr =
          prefs.getString(_keyReplayGainMode) ?? ReplayGainMode.track.name;
      final replayGainMode = ReplayGainMode.values.firstWhere(
        (e) => e.name == replayGainModeStr,
        orElse: () => ReplayGainMode.track,
      );
      final replayGainPreampWithRgRaw =
          prefs.getDouble(_keyReplayGainPreampWithRg) ?? 0.0;
      final replayGainPreampWithoutRgRaw =
          prefs.getDouble(_keyReplayGainPreampWithoutRg) ?? -3.0;
      // Clamp corrupted prefs into the valid preamp range.
      final replayGainPreampWithRg = replayGainPreampWithRgRaw.isFinite
          ? replayGainPreampWithRgRaw.clamp(-12.0, 12.0)
          : 0.0;
      final replayGainPreampWithoutRg =
          replayGainPreampWithoutRgRaw.isFinite
              ? replayGainPreampWithoutRgRaw.clamp(-12.0, 12.0)
              : -3.0;

      final streamingQualityStr =
          prefs.getString(_keyStreamingQuality) ?? YtmAudioQuality.high.name;
      final streamingQuality = YtmAudioQuality.values.firstWhere(
        (e) => e.name == streamingQualityStr,
        orElse: () => YtmAudioQuality.high,
      );

      final downloadQualityStr =
          prefs.getString(_keyDownloadQuality) ?? YtmAudioQuality.high.name;
      final downloadQuality = YtmAudioQuality.values.firstWhere(
        (e) => e.name == downloadQualityStr,
        orElse: () => YtmAudioQuality.high,
      );

      // Proxy Settings
      final proxyTypeStr =
          prefs.getString(_keyProxyType) ?? AppProxyType.http.name;
      final proxyType = AppProxyType.values.firstWhere(
        (e) => e.name == proxyTypeStr,
        orElse: () => AppProxyType.http,
      );
      final proxyHost = prefs.getString(_keyProxyHost) ?? '';
      final proxyPortRaw = prefs.getInt(_keyProxyPort) ?? 8080;
      final proxyPort = proxyPortRaw.clamp(1, 65535);
      final proxyUsername = prefs.getString(_keyProxyUsername) ?? '';

      // Legacy proxy password migration already handled above (lines 164-186)
      // No second migration needed.

      // Remote backend decommissioned: purge any stored backend token and
      // force on-device prefs so legacy installs migrate on next launch.
      try {
        await _secureStorage.delete(key: 'xdm_backend_token_secure');
        await prefs.remove(PrefsKeys.ytdlpBackendToken);
        await prefs.setBool(PrefsKeys.ytdlpBackendEnabled, false);
        await prefs.setString(
            PrefsKeys.extractorEngine, ExtractorEngine.onDevice.name);
        await prefs.setBool(PrefsKeys.syncCookiesToBackend, false);
      } catch (_) {}

      final proxyBypassHosts =
          prefs.getString(_keyProxyBypassHosts) ?? 'localhost, 127.0.0.1';

      List<ProxyEntry> proxyList = [];
      final proxyListRaw = prefs.getString(_keyProxyList);
      if (proxyListRaw != null && proxyListRaw.isNotEmpty) {
        try {
          final decoded = jsonDecode(proxyListRaw) as List<dynamic>;
          final maps = decoded.cast<Map<String, dynamic>>();
          final secrets = await _readProxyPoolSecrets();

          // Builds before the credential split wrote pool passwords straight
          // into this JSON. Harvest them so the re-save below can move them
          // into secure storage and strip them from prefs.
          var hadPlaintext = false;
          for (final map in maps) {
            final legacy = map['password'] as String?;
            final id = map['id'] as String?;
            if (legacy != null && legacy.isNotEmpty && id != null) {
              hadPlaintext = true;
              secrets.putIfAbsent(id, () => legacy);
            }
          }

          proxyList = maps
              .map(ProxyEntry.fromMap)
              .map(
                (e) => secrets.containsKey(e.id)
                    ? e.copyWith(password: secrets[e.id])
                    : e,
              )
              .where((e) => e.isValid)
              .toList();

          if (hadPlaintext) {
            await _saveProxyList(proxyList);
          }
        } catch (_) {}
      }

      // Proxy Settings
      final proxyEnabled = prefs.getBool(_keyProxyEnabled) ?? false;

      // Theme color source
      final ThemeColorSource themeColorSource;
      final sourceStr = prefs.getString(_keyThemeColorSource);
      if (sourceStr != null) {
        themeColorSource = ThemeColorSource.values.firstWhere(
          (e) => e.name == sourceStr,
          orElse: () => ThemeColorSource.artwork,
        );
      } else if (prefs.containsKey(_keyDynamicTheme)) {
        themeColorSource = (prefs.getBool(_keyDynamicTheme) ?? true)
            ? ThemeColorSource.artwork
            : ThemeColorSource.custom;
      } else {
        themeColorSource = ThemeColorSource.artwork;
      }

      // Effect keys are owned by EqualizerManager. Prefer its live values so
      // the settings screen can never diverge from the DSP engine; fall back
      // to the on-disk snapshot when the manager has not been created yet.
      final effectManager = getIt.isRegistered<EqualizerManager>()
          ? getIt<EqualizerManager>()
          : null;

      final strictBitPerfectLoaded =
          prefs.getBool(PrefsKeys.strictBitPerfect) ?? false;
      final followTrackSampleRateLoaded =
          prefs.getBool(PrefsKeys.followTrackSampleRate) ?? false;
      // Default to PCM when unset or unrecognized. DoP is never auto-enabled.
      final dsdOutputModeLoaded = DsdOutputMode.values.firstWhere(
        (e) =>
            e.name == (prefs.getString(PrefsKeys.dsdOutputMode) ?? 'pcm'),
        orElse: () => DsdOutputMode.pcm,
      );
      // Default to Normal so existing users land on the curated experience.
      final experienceModeLoaded = ExperienceMode.fromName(
          prefs.getString(PrefsKeys.experienceMode));

      final newState = state.copyWith(
        // Crossfade > 0 forces gapless OFF (they are mutually exclusive), even
        // if legacy prefs stored both on.
        gaplessPlayback:
            ((prefs.getDouble(_keyCrossfade) ?? state.crossfadeSeconds) > 0.01)
                ? false
                : (prefs.getBool(_keyGapless) ?? state.gaplessPlayback),
        crossfadeSeconds:
            prefs.getDouble(_keyCrossfade) ?? state.crossfadeSeconds,
        minDurationSec: prefs.getInt(_keyMinDuration) ?? state.minDurationSec,
        autoHideSystemMedia:
            prefs.getBool(_keyAutoHideSystemMedia) ?? state.autoHideSystemMedia,
        themeColorSource: themeColorSource,
        resumeAfterInterruption: prefs.getBool(_keyResumeAfterInterruption) ??
            state.resumeAfterInterruption,
        waveformSeekBarEnabled:
            prefs.getBool(_keyWaveformSeekBar) ?? state.waveformSeekBarEnabled,
        themeMode: themeMode,
        autoThemeByTime:
            prefs.getBool(_keyAutoThemeByTime) ?? state.autoThemeByTime,
        highContrast: prefs.getBool(_keyHighContrast) ?? state.highContrast,
        languageCode: prefs.getString(_keyLanguageCode) ?? state.languageCode,
        customAccentColorValue: customAccentValue,
        playerThemeMode: playerThemeMode,
        visualizerStyle: visualizerStyle,
        miniPlayerSwipeLeft: miniPlayerSwipeLeft,
        miniPlayerSwipeRight: miniPlayerSwipeRight,
        nowPlayingDoubleTap: nowPlayingDoubleTap,
        nowPlayingArtworkSwipe: nowPlayingArtworkSwipe,
        replayGainMode: replayGainMode,
        replayGainPreampWithRg: replayGainPreampWithRg,
        replayGainPreampWithoutRg: replayGainPreampWithoutRg,
        streamingQuality: streamingQuality,
        downloadQuality: downloadQuality,
        wifiOnlyMode: prefs.getBool(_keyWifiOnlyMode) ?? state.wifiOnlyMode,
        offlineOnlyMode:
            prefs.getBool(_keyOfflineOnlyMode) ?? state.offlineOnlyMode,
        proxyEnabled: proxyEnabled,
        proxyType: proxyType,
        proxyHost: proxyHost,
        proxyPort: proxyPort,
        proxyUsername: proxyUsername,
        hasProxyPassword: proxyPassword.isNotEmpty,
        proxyBypassHosts: proxyBypassHosts,
        proxyList: proxyList,
        extractorEngine: ExtractorEngine.onDevice,
        ytdlpBackendEnabled: false,
        ytdlpBackendUrl:
            prefs.getString(PrefsKeys.ytdlpBackendUrl) ?? state.ytdlpBackendUrl,
        ytdlpBackendToken: '',
        syncCookiesToBackend: false,
        bitPerfectOutput: strictBitPerfectLoaded
            ? true
            : (prefs.getBool(PrefsKeys.bitPerfectOutput) ??
                state.bitPerfectOutput),
        bypassDspOnBitPerfect: strictBitPerfectLoaded
            ? true
            : (prefs.getBool(PrefsKeys.bypassDspOnBitPerfect) ??
                state.bypassDspOnBitPerfect),
        strictBitPerfect: strictBitPerfectLoaded,
        followTrackSampleRate: strictBitPerfectLoaded
            ? true
            : followTrackSampleRateLoaded,
        dsdOutputMode: dsdOutputModeLoaded,
        experienceMode: experienceModeLoaded,
        currentOutputDevice:
            _hiResAudioService.currentOutputInfo ?? state.currentOutputDevice,
        crossfeedEnabled: effectManager?.isCrossfeedEnabled ??
            (prefs.getBool(PrefsKeys.crossfeedEnabled) ??
                state.crossfeedEnabled),
        crossfeedDelayUs: effectManager?.crossfeedDelayUs ??
            (prefs.getDouble(PrefsKeys.crossfeedDelayUs) ??
                state.crossfeedDelayUs),
        crossfeedFeedDb: effectManager?.crossfeedFeedDb ??
            (prefs.getDouble(PrefsKeys.crossfeedFeedDb) ??
                state.crossfeedFeedDb),
        limiterEnabled: effectManager?.isLimiterEnabled ??
            (prefs.getBool(PrefsKeys.lookaheadLimiterEnabled) ??
                state.limiterEnabled),
        limiterLookaheadMs: effectManager?.limiterLookaheadMs ??
            (prefs.getDouble('setting_lookahead_limiter_lookahead_ms') ??
                state.limiterLookaheadMs),
        limiterThresholdDb: effectManager?.limiterThresholdDb ??
            (prefs.getDouble(PrefsKeys.lookaheadLimiterThresholdDb) ??
                state.limiterThresholdDb),
        limiterReleaseMs: effectManager?.limiterReleaseMs ??
            (prefs.getDouble(PrefsKeys.lookaheadLimiterReleaseMs) ??
                state.limiterReleaseMs),
        reverbEnabled: effectManager?.isReverbEnabled ??
            (prefs.getBool(PrefsKeys.convolutionReverbEnabled) ??
                state.reverbEnabled),
        reverbPreset: effectManager?.reverbPreset ??
            (prefs.getInt(PrefsKeys.convolutionReverbPreset) ??
                state.reverbPreset),
        reverbWetDry: effectManager?.reverbWetDry ??
            (prefs.getDouble(PrefsKeys.convolutionReverbWetDry) ??
                state.reverbWetDry),
        stereoBalance: effectManager?.stereoBalance ??
            (prefs.getDouble(PrefsKeys.stereoBalance) ?? state.stereoBalance),
        monoMix: effectManager?.monoMix ??
            (prefs.getBool(PrefsKeys.monoMix) ?? state.monoMix),
        sincResamplerEnabled: effectManager?.isSincResamplerEnabled ??
            (prefs.getBool(PrefsKeys.sincResamplerEnabled) ??
                state.sincResamplerEnabled),
        dspPreference:
            prefs.getString(_keyDspPreference) ?? state.dspPreference,
        systemEffectsPolicy: prefs.getString(PrefsKeys.systemEffectsPolicy) ??
            state.systemEffectsPolicy,
        bluetoothLatencyOffsetMs:
            prefs.getInt(PrefsKeys.bluetoothLatencyOffsetMs) ??
                state.bluetoothLatencyOffsetMs,
        hedgedResolutionEnabled:
            prefs.getBool(PrefsKeys.hedgedResolutionEnabled) ?? true,
        adaptiveQualityEnabled:
            prefs.getBool(PrefsKeys.adaptiveQualityEnabled) ?? true,
        duckingMode:
            prefs.getString(PrefsKeys.duckingMode) ?? 'duck',
        duckingLevel:
            prefs.getDouble(PrefsKeys.duckingLevel) ?? 0.3,
        multiOutputMode:
            prefs.getString(PrefsKeys.multiOutputMode) ?? 'systemDefault',
        dspSnapshotEnabled:
            prefs.getBool(PrefsKeys.dspSnapshotEnabled) ?? true,
        silenceSkipSensitivity:
            prefs.getInt(PrefsKeys.silenceSkipSensitivity) ?? 0,
        sessionLogEnabled:
            prefs.getBool(PrefsKeys.audioSessionLogEnabled) ?? true,
        outputFormatNegotiationEnabled: prefs
                .getBool(PrefsKeys.outputFormatNegotiationEnabled) ??
            false,
        floatOutputEnabled:
            prefs.getBool(PrefsKeys.floatOutputEnabled) ?? false,
        aaudioOutputEnabled:
            prefs.getBool(PrefsKeys.aaudioOutputEnabled) ?? false,
        aaudioPreferExclusive:
            prefs.getBool(PrefsKeys.aaudioPreferExclusive) ?? true,
        aaudioTargetBufferMs:
            prefs.getInt(PrefsKeys.aaudioTargetBufferMs) ?? 150,
        sincResamplerQuality:
            prefs.getInt(PrefsKeys.sincResamplerQuality) ?? 3,
        bpmSyncCrossfadeEnabled:
            prefs.getBool(PrefsKeys.bpmSyncCrossfadeEnabled) ?? false,
      );

      // A proxy edit made while this load was in flight must win over the
      // on-disk snapshot, otherwise the user's change silently reverts.
      final previous = state;
      final loadedState = _proxyDirty
          ? newState.copyWith(
              proxyEnabled: previous.proxyEnabled,
              proxyType: previous.proxyType,
              proxyHost: previous.proxyHost,
              proxyPort: previous.proxyPort,
              proxyUsername: previous.proxyUsername,
              hasProxyPassword: previous.hasProxyPassword,
              proxyBypassHosts: previous.proxyBypassHosts,
              proxyList: previous.proxyList,
            )
          : newState;

      if (!_proxyDirty) {
        _proxyPassword = proxyPassword;
      }

      // Emit before the platform round-trips below: main.dart drives themeMode,
      // accent and locale from this state, so deferring it renders the default
      // theme and locale for as long as the native calls take.
      safeEmit(loadedState);

      if (getIt.isRegistered<EqualizerManager>()) {
        await getIt<EqualizerManager>().setDspPreference(loadedState.dspPreference);
      } else {
        await AudioEffectsChannel().setDspPreference(loadedState.dspPreference);
      }
      try {
        final status = await AudioEffectsChannel().setSystemEffectsPolicy(
          loadedState.systemEffectsPolicy,
          isHiResOrBitPerfect: loadedState.bitPerfectOutput,
        );
        safeEmit(state.copyWith(systemEffectsStatus: status));
      } catch (_) {}
      if (loadedState.bitPerfectOutput) {
        await _hiResAudioService.setBitPerfectMode(true);
      }
      if (loadedState.bitPerfectOutput && loadedState.bypassDspOnBitPerfect) {
        // Re-assert the DSP-bypass policy at boot: without this the Kotlin
        // effects plugin keeps its default (bypass off) after a restart and
        // the saved bit-perfect conflict rule is not enforced this session.
        if (getIt.isRegistered<EqualizerManager>()) {
          await getIt<EqualizerManager>().setBypassDspForBitPerfect(true);
        } else {
          await AudioEffectsChannel().setBypassDspForBitPerfect(true);
        }
      }
      final savedSampleRate = prefs.getInt('target_output_sample_rate') ?? 0;
      final savedBitDepth = prefs.getInt('target_output_bit_depth') ?? 0;
      if (savedSampleRate > 0 || savedBitDepth > 0) {
        await _hiResAudioService.setTargetOutputFormat(
          sampleRate: savedSampleRate,
          bitDepth: savedBitDepth,
        );
      }
      await refreshOutputDevice();
      // FIX-E01: Wrap _syncProxySettings in try/catch so native proxy failure doesn't abort settings load
      try {
        await _syncProxySettings(activeProxyConfig);
      } catch (e) {
        debugPrint('[SettingsCubit] Failed to sync proxy settings during load: $e');
      }
      // Resume scheduled theming across restarts only when the user opted in.
      _startThemeScheduler();
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to load settings preferences from SharedPreferences',
        error: e,
        stackTrace: st,
        category: 'SettingsCubit',
      );
    }
  }

  Future<void> setGapless(bool value) async {
    // Prevent gapless + crossfade together — auto-disable crossfade and inform user
    if (value && state.crossfadeSeconds > 0.01) {
      safeEmit(
        state.copyWith(
          gaplessPlayback: true,
          crossfadeSeconds: 0.0,
          errorMessage: AudioConflicts.gaplessBlockedByCrossfade(
                state.crossfadeSeconds,
              ) ??
              'Crossfade disabled: gapless requires 0 s.',
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyGapless, true);
      await prefs.setDouble(_keyCrossfade, 0.0);
      return;
    }
    safeEmit(state.copyWith(gaplessPlayback: value, errorMessage: null));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGapless, value);
  }

  Future<void> setCrossfade(double seconds) async {
    final clamped = seconds.clamp(0.0, 12.0);
    final bitPerfectBlock = AudioConflicts.crossfadeBlockedByBitPerfect(
      bitPerfectOutput: state.bitPerfectOutput,
      bypassDspOnBitPerfect: state.bypassDspOnBitPerfect,
      device: state.currentOutputDevice,
    );
    if (clamped > 0.01 && bitPerfectBlock != null) {
      safeEmit(state.copyWith(errorMessage: bitPerfectBlock));
      return;
    }
    if (clamped > 0.01 && state.gaplessPlayback) {
      // Crossfade needs gapless OFF — auto-disable gapless
      safeEmit(
        state.copyWith(
          crossfadeSeconds: clamped,
          gaplessPlayback: false,
          errorMessage: AudioConflicts.crossfadeBlockedByGapless(true) ??
              'Gapless disabled: crossfade requires gapless OFF.',
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyCrossfade, clamped);
      await prefs.setBool(_keyGapless, false);
      return;
    }
    safeEmit(state.copyWith(crossfadeSeconds: clamped, errorMessage: null));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyCrossfade, clamped);
  }

  Future<void> setMinDuration(int seconds) async {
    final clamped = seconds.clamp(0, 300);
    safeEmit(state.copyWith(minDurationSec: clamped));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMinDuration, clamped);
  }

  Future<int> getMinFileSizeKb() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyMinFileSizeKb) ?? 0;
  }

  Future<void> setMinFileSizeKb(int kb) async {
    final clamped = kb.clamp(0, 5000);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMinFileSizeKb, clamped);
  }

  Future<void> setAutoHideSystemMedia(bool value) async {
    MediaScannerService.clearNomediaCache();
    safeEmit(state.copyWith(autoHideSystemMedia: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoHideSystemMedia, value);
  }

  Future<void> setThemeColorSource(ThemeColorSource source) async {
    safeEmit(state.copyWith(themeColorSource: source));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeColorSource, source.name);
    await prefs.setBool(_keyDynamicTheme, source == ThemeColorSource.artwork);
  }

  Future<void> setDynamicTheming(bool value) => setThemeColorSource(
        value ? ThemeColorSource.artwork : ThemeColorSource.custom,
      );

  Future<void> setResumeAfterInterruption(bool value) async {
    safeEmit(state.copyWith(resumeAfterInterruption: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyResumeAfterInterruption, value);
  }

  Future<void> setWaveformSeekBar(bool value) async {
    safeEmit(state.copyWith(waveformSeekBarEnabled: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyWaveformSeekBar, value);
  }

  /// Switches between the curated Normal experience and the full Professional
  /// control surface. Emitting rebuilds every settings/player surface that
  /// watches [SettingsState.isProfessional].
  Future<void> setExperienceMode(ExperienceMode mode) async {
    safeEmit(state.copyWith(experienceMode: mode));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.experienceMode, mode.name);
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    safeEmit(state.copyWith(themeMode: mode));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, mode.name);
    _syncSystemUiOverlay(mode);
  }

  /// Opt-in day/night theme switching. When enabled, the scheduler re-checks
  /// the schedule immediately so the toggle takes effect without waiting for
  /// the next 15-minute tick.
  Future<void> setAutoThemeByTime(bool value) async {
    safeEmit(state.copyWith(autoThemeByTime: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoThemeByTime, value);
    if (value) {
      _startThemeScheduler();
    } else {
      _themeScheduler?.stopScheduler();
    }
  }

  Future<void> setHighContrast(bool value) async {
    safeEmit(state.copyWith(highContrast: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHighContrast, value);
  }

  /// Keeps the Android status/nav bars in sync with the app theme so a
  /// light theme never leaves light-on-light system chrome.
  void _syncSystemUiOverlay(AppThemeMode mode) {
    try {
      final isLight = mode == AppThemeMode.light;
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            isLight ? Brightness.dark : Brightness.light,
        statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: isLight ? Colors.white : Colors.black,
        systemNavigationBarIconBrightness:
            isLight ? Brightness.dark : Brightness.light,
      ));
    } catch (_) {}
  }

  Future<void> setLanguage(String languageCode) async {
    safeEmit(state.copyWith(languageCode: languageCode));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLanguageCode, languageCode);
  }

  Future<void> setCustomAccentColor(Color color) async {
    int colorVal;
    try {
      colorVal = (color as dynamic).toARGB32() as int;
    } catch (_) {
      colorVal = color.toARGB32();
    }
    safeEmit(state.copyWith(customAccentColorValue: colorVal));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCustomAccent, colorVal);
  }

  Future<void> setPlayerThemeMode(PlayerThemeMode mode) async {
    safeEmit(state.copyWith(playerThemeMode: mode));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPlayerThemeMode, mode.name);
  }

  Future<void> setVisualizerStyle(VisualizerStyle style) async {
    safeEmit(state.copyWith(visualizerStyle: style));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyVisualizerStyle, style.name);
  }

  Future<void> setMiniPlayerSwipeLeft(MiniPlayerSwipeAction action) async {
    safeEmit(state.copyWith(miniPlayerSwipeLeft: action));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMiniPlayerSwipeLeft, action.name);
  }

  Future<void> setMiniPlayerSwipeRight(MiniPlayerSwipeAction action) async {
    safeEmit(state.copyWith(miniPlayerSwipeRight: action));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMiniPlayerSwipeRight, action.name);
  }

  Future<void> setNowPlayingDoubleTap(NowPlayingDoubleTapAction action) async {
    safeEmit(state.copyWith(nowPlayingDoubleTap: action));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNowPlayingDoubleTap, action.name);
  }

  Future<void> setNowPlayingArtworkSwipe(
    NowPlayingArtworkSwipeAction action,
  ) async {
    safeEmit(state.copyWith(nowPlayingArtworkSwipe: action));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNowPlayingArtworkSwipe, action.name);
  }

  Future<void> setReplayGainMode(ReplayGainMode mode) async {
    if (mode != ReplayGainMode.off) {
      final blocked = AudioConflicts.replayGainBlockedByBitPerfect(
        bitPerfectOutput: state.bitPerfectOutput,
        bypassDspOnBitPerfect: state.bypassDspOnBitPerfect,
        device: state.currentOutputDevice,
      );
      if (blocked != null) {
        safeEmit(state.copyWith(errorMessage: blocked));
        return;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyReplayGainMode, mode.name);
    // PlayerCubit reacts to this state emission by re-applying the gain. Save
    // first so AudioHandler's cached preferences cannot calculate using the
    // previous mode (which made ReplayGain look enabled but sound unchanged).
    safeEmit(state.copyWith(replayGainMode: mode, errorMessage: null));
  }

  Future<void> setReplayGainPreampWithRg(double db) async {
    final clamped = db.clamp(-15.0, 15.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyReplayGainPreampWithRg, clamped);
    safeEmit(state.copyWith(replayGainPreampWithRg: clamped));
  }

  Future<void> setReplayGainPreampWithoutRg(double db) async {
    final clamped = db.clamp(-15.0, 15.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyReplayGainPreampWithoutRg, clamped);
    safeEmit(state.copyWith(replayGainPreampWithoutRg: clamped));
  }

  Future<void> setStreamingQuality(YtmAudioQuality quality) async {
    safeEmit(state.copyWith(streamingQuality: quality));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyStreamingQuality, quality.name);
  }

  Future<void> setDownloadQuality(YtmAudioQuality quality) async {
    safeEmit(state.copyWith(downloadQuality: quality));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDownloadQuality, quality.name);
  }

  Future<void> setWifiOnlyMode(bool enabled) async {
    safeEmit(state.copyWith(wifiOnlyMode: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyWifiOnlyMode, enabled);
  }

  Future<void> setOfflineOnlyMode(bool enabled) async {
    safeEmit(state.copyWith(offlineOnlyMode: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOfflineOnlyMode, enabled);
  }

  // --- Proxy Settings Actions ---

  Future<void> setProxyEnabled(bool enabled) async {
    _proxyDirty = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyProxyEnabled, enabled);
    final updated = state.copyWith(proxyEnabled: enabled);
    safeEmit(updated);
    if (!enabled) {
      await _syncProxySettings(const ProxyConfig(enabled: false));
    } else {
      await _syncProxySettings(activeProxyConfig.copyWith(enabled: true));
    }
  }

  Future<void> setProxySettings({
    required bool enabled,
    required AppProxyType type,
    required String host,
    required int port,
    String? username,
    String? password,
    String? bypassHosts,
  }) async {
    _proxyDirty = true;
    final trimmedHost = host.trim();
    if (enabled) {
      final isIPv4 = RegExp(
              r'^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$')
          .hasMatch(trimmedHost);
      final isIPv6 = RegExp(r'^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$')
              .hasMatch(trimmedHost) ||
          trimmedHost == '::1' ||
          trimmedHost.startsWith('fe80:');
      final isHostname = RegExp(
              r'^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$')
          .hasMatch(trimmedHost);
      final isLocalhost =
          trimmedHost == 'localhost' || trimmedHost == '127.0.0.1';
      if (trimmedHost.isEmpty ||
          (!isIPv4 && !isIPv6 && !isHostname && !isLocalhost)) {
        safeEmit(state.copyWith(errorMessage: 'Invalid proxy host format'));
        return;
      }
      if (port < 1 || port > 65535) {
        safeEmit(state.copyWith(
            errorMessage: 'Proxy port must be between 1 and 65535'));
        return;
      }
    }

    final pass = password ?? '';
    _proxyPassword = pass;
    final newConfig = ProxyConfig(
      enabled: enabled,
      type: type,
      host: trimmedHost,
      port: port,
      username: username?.trim() ?? '',
      password: pass,
      bypassHosts: bypassHosts ?? 'localhost, 127.0.0.1',
    );

    final updated = state.copyWith(
      proxyEnabled: newConfig.enabled,
      proxyType: newConfig.type,
      proxyHost: newConfig.host,
      proxyPort: newConfig.port,
      proxyUsername: newConfig.username,
      hasProxyPassword: newConfig.password.isNotEmpty,
      proxyBypassHosts: newConfig.bypassHosts,
    );

    safeEmit(updated);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyProxyEnabled, newConfig.enabled);
    await prefs.setString(_keyProxyType, newConfig.type.name);
    await prefs.setString(_keyProxyHost, newConfig.host);
    await prefs.setInt(_keyProxyPort, newConfig.port);
    await prefs.setString(_keyProxyUsername, newConfig.username);
    try {
      if (newConfig.password.isNotEmpty) {
        await _secureStorage.write(
          key: _keyProxyPasswordSecure,
          value: newConfig.password,
        );
      } else {
        await _secureStorage.delete(key: _keyProxyPasswordSecure);
      }
    } catch (_) {}
    await prefs.remove(_keyProxyPassword);
    await prefs.setString(_keyProxyBypassHosts, newConfig.bypassHosts);

    await _syncProxySettings(newConfig);
  }

  /// Tests connectivity through the provided or current proxy config.
  Future<({bool success, int latencyMs, String? error})> testProxyConnection([
    ProxyConfig? config,
  ]) async {
    final configToTest = config ?? activeProxyConfig;
    return AppHttpOverrides.instance.testConnection(configToTest: configToTest);
  }

  /// Persists the pool with credentials split out: the prefs JSON is
  /// password-free and the secrets live in secure storage, keyed by entry ID.
  Future<void> _saveProxyList(List<ProxyEntry> list) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = list.map((e) => e.toMap()..remove('password')).toList();
    await prefs.setString(_keyProxyList, jsonEncode(jsonList));

    final secrets = <String, String>{
      for (final e in list)
        if (e.password.isNotEmpty) e.id: e.password,
    };
    try {
      if (secrets.isEmpty) {
        await _secureStorage.delete(key: _keyProxyListPasswordsSecure);
      } else {
        await _secureStorage.write(
          key: _keyProxyListPasswordsSecure,
          value: jsonEncode(secrets),
        );
      }
    } catch (e, st) {
      // The pool itself is saved either way; only the credentials are lost, and
      // failing loudly here beats silently writing them back out in plaintext.
      ErrorLogger.log(
        'Failed to persist proxy pool credentials to secure storage',
        error: e,
        stackTrace: st,
        category: 'SettingsCubit',
      );
    }
  }

  /// Imports multiple proxies parsed from raw multi-line text or file content.
  /// Returns the count of newly added proxies.
  Future<int> importProxiesFromText(
    String rawText, {
    bool autoSelectFirst = false,
  }) async {
    final parsed = ProxyEntry.parseList(rawText);
    if (parsed.isEmpty) return 0;

    final existing = List<ProxyEntry>.from(state.proxyList);
    final existingKeys =
        existing.map((e) => '${e.host}:${e.port}:${e.username}').toSet();

    int addedCount = 0;
    for (final p in parsed) {
      final key = '${p.host}:${p.port}:${p.username}';
      if (!existingKeys.contains(key)) {
        existing.add(p);
        existingKeys.add(key);
        addedCount++;
      }
    }

    if (addedCount > 0) {
      safeEmit(state.copyWith(proxyList: existing));
      await _saveProxyList(existing);
      if (autoSelectFirst && existing.isNotEmpty) {
        await selectProxyEntry(parsed.first);
      }
    }
    return addedCount;
  }

  /// Adds or updates a single proxy entry in the pool.
  Future<void> addProxyEntry(
    ProxyEntry entry, {
    bool autoSelect = false,
  }) async {
    final existing = List<ProxyEntry>.from(state.proxyList);
    final index = existing.indexWhere(
      (e) => e.id == entry.id || (e.host == entry.host && e.port == entry.port),
    );
    if (index >= 0) {
      existing[index] = entry;
    } else {
      existing.add(entry);
    }
    safeEmit(state.copyWith(proxyList: existing));
    await _saveProxyList(existing);
    if (autoSelect) {
      await selectProxyEntry(entry);
    }
  }

  /// Removes a proxy from the pool by ID.
  Future<void> removeProxyEntry(String id) async {
    final updated = state.proxyList.where((e) => e.id != id).toList();
    safeEmit(state.copyWith(proxyList: updated));
    await _saveProxyList(updated);
  }

  /// Clears the entire proxy pool.
  Future<void> clearProxyList() async {
    safeEmit(state.copyWith(proxyList: []));
    await _saveProxyList([]);
  }

  /// Selects a proxy from the pool and activates it as the current active proxy.
  Future<void> selectProxyEntry(ProxyEntry entry) async {
    await setProxySettings(
      enabled: true,
      type: entry.type,
      host: entry.host,
      port: entry.port,
      username: entry.username,
      password: entry.password,
      bypassHosts: state.proxyBypassHosts,
    );
  }

  /// Concurrently tests all proxies in the pool in parallel batches of 5
  /// against the probe endpoint, updating live latency and working status for each proxy.
  Future<void> testAllProxies() async {
    if (state.proxyList.isEmpty || state.isTestingAllProxies) return;

    safeEmit(state.copyWith(isTestingAllProxies: true));
    try {
      final ids = state.proxyList.map((e) => e.id).toList();

      for (int i = 0; i < ids.length; i += 5) {
        // Re-read the live pool for every batch: the user can add or remove
        // proxies while the probes run, and writing back a start-of-run
        // snapshot would resurrect removed entries and drop new ones.
        final batchIds = ids.sublist(i, math.min(i + 5, ids.length)).toSet();
        final batch =
            state.proxyList.where((e) => batchIds.contains(e.id)).toList();
        if (batch.isEmpty) continue;

        _mergeProxyEntries({
          for (final e in batch) e.id: e.copyWith(isTesting: true),
        });

        final probed = await Future.wait(batch.map(_probeProxyEntry));
        if (isClosed) return;
        _mergeProxyEntries({for (final e in probed) e.id: e});
      }
      await _saveProxyList(state.proxyList);
    } finally {
      safeEmit(state.copyWith(isTestingAllProxies: false));
    }
  }

  /// Writes probe results back onto the current pool by ID, leaving entries the
  /// user touched mid-run alone.
  void _mergeProxyEntries(Map<String, ProxyEntry> updates) {
    safeEmit(
      state.copyWith(
        proxyList: [
          for (final entry in state.proxyList) updates[entry.id] ?? entry,
        ],
      ),
    );
  }

  Future<ProxyEntry> _probeProxyEntry(ProxyEntry entry) async {
    try {
      final result = await AppHttpOverrides.instance.testConnection(
        configToTest: entry.toProxyConfig(enabled: true),
        timeout: const Duration(seconds: 10),
      );
      return entry.copyWith(
        isTesting: false,
        isWorking: result.success,
        latencyMs: result.latencyMs,
        lastError: result.error,
        clearLastError: result.error == null,
      );
    } catch (e) {
      return entry.copyWith(
        isTesting: false,
        isWorking: false,
        lastError: e.toString(),
      );
    }
  }

  /// Tests a single proxy entry in the pool by its ID.
  Future<void> testSingleProxyEntry(String id) async {
    final index = state.proxyList.indexWhere((e) => e.id == id);
    if (index < 0) return;

    final entry = state.proxyList[index];
    _mergeProxyEntries({id: entry.copyWith(isTesting: true)});

    final probed = await _probeProxyEntry(entry);
    if (isClosed) return;
    _mergeProxyEntries({id: probed});
    await _saveProxyList(state.proxyList);
  }

  /// Sorts proxy entries by lowest latency first, followed by unverified/failed ones.
  Future<void> sortProxiesByLatency() async {
    final list = List<ProxyEntry>.from(state.proxyList);
    list.sort((a, b) {
      if (a.isWorking == true && b.isWorking == true) {
        return (a.latencyMs ?? 99999).compareTo(b.latencyMs ?? 99999);
      }
      if (a.isWorking == true && b.isWorking != true) return -1;
      if (a.isWorking != true && b.isWorking == true) return 1;
      return 0;
    });
    safeEmit(state.copyWith(proxyList: list));
    await _saveProxyList(list);
  }

  Future<void> setExtractorEngine(ExtractorEngine engine) async {
    // DISABLED: remote backend decommissioned — always on-device.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        PrefsKeys.extractorEngine, ExtractorEngine.onDevice.name);
    await prefs.setBool(PrefsKeys.ytdlpBackendEnabled, false);
    safeEmit(
      state.copyWith(
        extractorEngine: ExtractorEngine.onDevice,
        ytdlpBackendEnabled: false,
      ),
    );
  }

  Future<void> setYtdlpBackendEnabled(bool enabled) async {
    // DISABLED: remote backend decommissioned — always off.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.ytdlpBackendEnabled, false);
    await prefs.setString(
        PrefsKeys.extractorEngine, ExtractorEngine.onDevice.name);
    safeEmit(
      state.copyWith(
          ytdlpBackendEnabled: false,
          extractorEngine: ExtractorEngine.onDevice),
    );
  }

  Future<void> setYtdlpBackendUrl(String url) async {
    // DISABLED: no-op, kept for API compatibility.
    return;
  }

  Future<void> setYtdlpBackendToken(String token) async {
    // DISABLED: purge instead of storing.
    try {
      await _secureStorage.delete(key: 'xdm_backend_token_secure');
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PrefsKeys.ytdlpBackendToken);
    safeEmit(state.copyWith(ytdlpBackendToken: ''));
  }

  Future<void> setSyncCookiesToBackend(bool value) async {
    // DISABLED: never sync cookies to a remote backend.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.syncCookiesToBackend, false);
    safeEmit(state.copyWith(syncCookiesToBackend: false));
  }

  Future<void> testYtdlpBackend() async {
    safeEmit(
      state.copyWith(
        isTestingYtdlpBackend: false,
        ytdlpBackendStatusMessage:
            'Remote yt-dlp backend is disabled (on-device only).',
        ytdlpBackendVersion: 'disabled',
        ytdlpBackendProxyCount: 0,
        ytdlpBackendCircuitState: 'open',
      ),
    );
  }

  Future<int> rescanLibrary() async {
    MediaScannerService.clearNomediaCache();
    safeEmit(
      state.copyWith(
        isScanning: true,
        scanResultCount: null,
        errorMessage: null,
      ),
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      final minSizeKb = prefs.getInt(_keyMinFileSizeKb) ?? 0;
      final count = await _scannerService.scanDeviceLibrary(
        ignoreShortFiles: state.minDurationSec > 0,
        minDurationSec: state.minDurationSec,
        minSizeKb: minSizeKb,
        autoHideSystemMedia: state.autoHideSystemMedia,
      );
      safeEmit(state.copyWith(isScanning: false, scanResultCount: count));
      return count;
    } catch (e) {
      safeEmit(state.copyWith(isScanning: false, errorMessage: e.toString()));
      return 0;
    }
  }

  Future<int> removeMissingFiles() async {
    try {
      if (!getIt.isRegistered<IMusicRepository>()) return 0;
      final result = await getIt<IMusicRepository>().hardDeleteMissingSongs();
      return result.fold<int>((_) => 0, (count) => count);
    } catch (e, st) {
      ErrorLogger.log('Failed to remove missing files',
          error: e, stackTrace: st, category: 'SettingsCubit');
      return 0;
    }
  }

  Future<void> setBitPerfectOutput(bool enabled) async {
    if (enabled) {
      final block = AudioConflicts.bitPerfectBlockedReason(
        state.currentOutputDevice,
      );
      if (block != null) {
        safeEmit(state.copyWith(errorMessage: block));
        return;
      }
    }
    safeEmit(
      state.copyWith(
        bitPerfectOutput: enabled,
        errorMessage: null,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.bitPerfectOutput, enabled);
    await _hiResAudioService.setBitPerfectMode(enabled);
    // Wire bypass: when bit-perfect enabled and user wants bypass, force DSP off via native
    if (enabled && state.bypassDspOnBitPerfect) {
      try {
        if (getIt.isRegistered<EqualizerManager>()) {
          await getIt<EqualizerManager>().setBypassDspForBitPerfect(true);
        } else {
          await AudioEffectsChannel().setBypassDspForBitPerfect(true);
        }
      } catch (_) {}
      // Also force ReplayGain off — software gain breaks bit-perfect
      if (state.replayGainMode != ReplayGainMode.off) {
        await prefs.setString(_keyReplayGainMode, ReplayGainMode.off.name);
        safeEmit(
          state.copyWith(
            replayGainMode: ReplayGainMode.off,
            errorMessage:
                'ReplayGain disabled: not compatible with Bit-Perfect bypass.',
          ),
        );
      }
    } else if (!enabled) {
      try {
        if (getIt.isRegistered<EqualizerManager>()) {
          await getIt<EqualizerManager>().setBypassDspForBitPerfect(false);
        } else {
          await AudioEffectsChannel().setBypassDspForBitPerfect(false);
        }
      } catch (_) {}
    }
    await refreshOutputDevice();
  }

  Future<void> setBypassDspOnBitPerfect(bool enabled) async {
    safeEmit(state.copyWith(bypassDspOnBitPerfect: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.bypassDspOnBitPerfect, enabled);
    // Apply immediately if bit-perfect is currently active
    if (state.bitPerfectOutput) {
      try {
        if (getIt.isRegistered<EqualizerManager>()) {
          await getIt<EqualizerManager>().setBypassDspForBitPerfect(enabled);
        } else {
          await AudioEffectsChannel().setBypassDspForBitPerfect(enabled);
        }
      } catch (_) {}
      await refreshOutputDevice();
    }
  }

  /// T2: follow the current track's native sample rate on every track change.
  /// The actual native call happens in PlayerCubit (it owns the track-change
  /// stream and the de-dupe state); this only persists the preference.
  Future<void> setFollowTrackSampleRate(bool value) async {
    safeEmit(state.copyWith(followTrackSampleRate: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.followTrackSampleRate, value);
  }

  /// T4: select the DSD (DSF/DFF) output transport.
  ///
  /// Refuses DoP unless the native probe has confirmed a compatible USB DAC, so
  /// the persisted preference can never claim native DSD on a path that cannot
  /// carry it. PCM is always allowed and is the default.
  Future<void> setDsdOutputMode(DsdOutputMode mode) async {
    if (mode == DsdOutputMode.dop && !state.dsdDopSupported) {
      safeEmit(state.copyWith(
        errorMessage:
            'DoP output requires a connected USB DAC that supports DSD over PCM.',
      ));
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.dsdOutputMode, mode.name);
    safeEmit(state.copyWith(dsdOutputMode: mode, errorMessage: null));
  }

  /// T3: strict bit-perfect (no resample). Enabling forces Bit-Perfect output,
  /// the DSP bypass and follow-track, then surfaces the conflict reason rather
  /// than silently muting stages. Disabled when the path cannot do bit-perfect.
  Future<void> setStrictBitPerfect(bool enabled) async {
    if (enabled) {
      final block = AudioConflicts.strictBitPerfectBlockedReason(
          state.currentOutputDevice);
      if (block != null) {
        safeEmit(state.copyWith(errorMessage: block));
        return;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.strictBitPerfect, enabled);
    if (!enabled) {
      safeEmit(state.copyWith(strictBitPerfect: false, errorMessage: null));
      return;
    }
    safeEmit(state.copyWith(
      strictBitPerfect: true,
      bitPerfectOutput: true,
      bypassDspOnBitPerfect: true,
      followTrackSampleRate: true,
      errorMessage: null,
    ));
    await prefs.setBool(PrefsKeys.bitPerfectOutput, true);
    await prefs.setBool(PrefsKeys.bypassDspOnBitPerfect, true);
    await prefs.setBool(PrefsKeys.followTrackSampleRate, true);
    await _hiResAudioService.setBitPerfectMode(true);
    try {
      if (getIt.isRegistered<EqualizerManager>()) {
        await getIt<EqualizerManager>().setBypassDspForBitPerfect(true);
      } else {
        await AudioEffectsChannel().setBypassDspForBitPerfect(true);
      }
    } catch (_) {}
    // Software gain would alter the bitstream; turn it off like the normal
    // Bit-Perfect path does.
    if (state.replayGainMode != ReplayGainMode.off) {
      await prefs.setString(_keyReplayGainMode, ReplayGainMode.off.name);
      if (!isClosed) {
        safeEmit(state.copyWith(replayGainMode: ReplayGainMode.off));
      }
    }
    await refreshOutputDevice();
  }

  /// Requests the media route move to [deviceId]. Returns true only when the
  /// platform actually accepted it; otherwise the system output panel is opened
  /// so the user can switch, since an unprivileged app cannot force the route.
  Future<bool> selectOutputDevice(int deviceId) async {
    final res = await _hiResAudioService.selectOutputDevice(deviceId);
    if (!res.success && res.requiresSystemPicker) {
      await _hiResAudioService.openOutputSwitcher();
    }
    await refreshOutputDevice();
    return res.success;
  }

  Future<bool> openOutputSwitcher() => _hiResAudioService.openOutputSwitcher();

  Future<void> clearOutputDevice() async {
    await _hiResAudioService.clearOutputDevice();
    await refreshOutputDevice();
  }

  Future<void> setTargetOutputSampleRate(int sampleRate) async {
    if (state.currentOutputDevice != null) {
      safeEmit(
        state.copyWith(
          currentOutputDevice: state.currentOutputDevice!.copyWith(
            targetSampleRate: sampleRate,
          ),
        ),
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('target_output_sample_rate', sampleRate);
    final bitDepth = state.currentOutputDevice?.targetBitDepth ?? 0;
    await _hiResAudioService.setTargetOutputFormat(
      sampleRate: sampleRate,
      bitDepth: bitDepth,
    );
    await refreshOutputDevice();
  }

  Future<void> setTargetOutputBitDepth(int bitDepth) async {
    if (state.currentOutputDevice != null) {
      safeEmit(
        state.copyWith(
          currentOutputDevice: state.currentOutputDevice!.copyWith(
            targetBitDepth: bitDepth,
          ),
        ),
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('target_output_bit_depth', bitDepth);
    final sampleRate = state.currentOutputDevice?.targetSampleRate ?? 0;
    await _hiResAudioService.setTargetOutputFormat(
      sampleRate: sampleRate,
      bitDepth: bitDepth,
    );
    await refreshOutputDevice();
  }

  // ── Bluetooth codec control ──────────────────────────────────────────────

  Future<void> setBluetoothCodec(String codec) async {
    // Optimistic UI: update btCodecName immediately
    if (state.currentOutputDevice != null) {
      safeEmit(
        state.copyWith(
          currentOutputDevice: state.currentOutputDevice!.copyWith(
            btCodecName: codec,
          ),
        ),
      );
    }
    await _hiResAudioService.setBluetoothCodec(codec);
    await refreshOutputDevice();
  }

  Future<void> setBluetoothSampleRate(int hz) async {
    if (state.currentOutputDevice != null) {
      safeEmit(
        state.copyWith(
          currentOutputDevice: state.currentOutputDevice!.copyWith(
            btSampleRateHz: hz,
          ),
        ),
      );
    }
    await _hiResAudioService.setBluetoothSampleRate(hz);
    await refreshOutputDevice();
  }

  Future<void> setBluetoothBitDepth(int bits) async {
    if (state.currentOutputDevice != null) {
      safeEmit(
        state.copyWith(
          currentOutputDevice: state.currentOutputDevice!.copyWith(
            btBitDepth: bits,
          ),
        ),
      );
    }
    await _hiResAudioService.setBluetoothBitDepth(bits);
    await refreshOutputDevice();
  }

  Future<void> setBluetoothLdacQuality(int mode) async {
    if (state.currentOutputDevice != null) {
      safeEmit(
        state.copyWith(
          currentOutputDevice: state.currentOutputDevice!.copyWith(
            btLdacQualityMode: mode,
          ),
        ),
      );
    }
    await _hiResAudioService.setBluetoothLdacQuality(mode);
    await refreshOutputDevice();
  }

  /// Triggers a runtime BLUETOOTH_CONNECT permission request (Android 12+).
  /// Falls back to opening app settings if already permanently denied.
  Future<void> requestBluetoothPermission() async {
    await _hiResAudioService.requestBluetoothPermission();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await refreshOutputDevice();
  }

  /// Opens Android Developer Options directly to the Bluetooth Audio Codec page.
  Future<void> openBluetoothDevOptions() async {
    await _hiResAudioService.openBluetoothDevOptions();
  }

  /// Probes the native DoP capability and stores the single [dop] gate in state.
  /// Used by the device-change listener; [refreshOutputDevice] folds the same
  /// probe into its emit.
  Future<void> _refreshDopSupport() async {
    final caps = await DsdDecoderHelper.probeDopCapabilities();
    if (isClosed) return;
    if (state.dsdDopSupported != caps.canUseDop) {
      safeEmit(state.copyWith(dsdDopSupported: caps.canUseDop));
    }
  }

  Future<void> refreshOutputDevice() async {
    final info = await _hiResAudioService.getAudioOutputInfo();
    final caps = await DsdDecoderHelper.probeDopCapabilities();
    final previous = state.currentOutputDevice;
    // Drop stale DAC targets when the route changes (e.g. USB -> speaker/BT);
    // otherwise a 192k DAC request is re-sent to the phone speaker.
    final routeChanged = previous != null &&
        (previous.deviceName != info.deviceName ||
            previous.activeDeviceType != info.activeDeviceType ||
            previous.isBluetooth != info.isBluetooth ||
            previous.isUsbDac != info.isUsbDac);
    final savedSampleRate = (!routeChanged &&
            previous?.targetSampleRate != null &&
            previous!.targetSampleRate > 0)
        ? previous.targetSampleRate
        : 0;
    final savedBitDepth = (!routeChanged &&
            previous?.targetBitDepth != null &&
            previous!.targetBitDepth > 0)
        ? previous.targetBitDepth
        : 0;

    if (isClosed) return;
    safeEmit(
      state.copyWith(
        currentOutputDevice: info.copyWith(
          targetSampleRate: info.targetSampleRate != 0
              ? info.targetSampleRate
              : savedSampleRate,
          targetBitDepth:
              info.targetBitDepth != 0 ? info.targetBitDepth : savedBitDepth,
        ),
        dsdDopSupported: caps.canUseDop,
      ),
    );
  }

  Future<void> setDspPreference(String preference) async {
    safeEmit(state.copyWith(dspPreference: preference));
    // EqualizerManager is the single writer for effect keys (including
    // dspPreference). Only persist directly when it is unavailable.
    if (getIt.isRegistered<EqualizerManager>()) {
      await getIt<EqualizerManager>().setDspPreference(preference);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDspPreference, preference);
    await AudioEffectsChannel().setDspPreference(preference);
  }

  Future<void> setLookaheadLimiter(
    bool enabled, {
    double? thresholdDb,
    double? releaseMs,
    double? lookaheadMs,
  }) async {
    final newEnabled = enabled;
    final newThreshold = thresholdDb ?? state.limiterThresholdDb;
    final newRelease = releaseMs ?? state.limiterReleaseMs;
    final newLookahead = lookaheadMs ?? state.limiterLookaheadMs;
    safeEmit(
      state.copyWith(
        limiterEnabled: newEnabled,
        limiterThresholdDb: newThreshold,
        limiterReleaseMs: newRelease,
        limiterLookaheadMs: newLookahead,
      ),
    );
    // EqualizerManager owns the limiter keys + persistence; delegating keeps
    // a single writer so this screen cannot diverge from the effect engine.
    if (getIt.isRegistered<EqualizerManager>()) {
      await getIt<EqualizerManager>().setLookaheadLimiter(
        newEnabled,
        thresholdDb: newThreshold,
        releaseMs: newRelease,
        lookaheadMs: newLookahead,
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.lookaheadLimiterEnabled, newEnabled);
    await prefs.setDouble(PrefsKeys.lookaheadLimiterThresholdDb, newThreshold);
    await prefs.setDouble(PrefsKeys.lookaheadLimiterReleaseMs, newRelease);
    await prefs.setDouble(
      'setting_lookahead_limiter_lookahead_ms',
      newLookahead,
    );
    await AudioEffectsChannel().setLimiterParams(
      newLookahead,
      newThreshold,
      newRelease,
    );
    await AudioEffectsChannel().setLimiterEnabled(newEnabled);
  }

  Future<void> setSystemEffectsPolicy(String policy) async {
    safeEmit(state.copyWith(systemEffectsPolicy: policy));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.systemEffectsPolicy, policy);
    try {
      final status = await AudioEffectsChannel().setSystemEffectsPolicy(
        policy,
        isHiResOrBitPerfect: state.bitPerfectOutput,
      );
      if (!isClosed) {
        safeEmit(state.copyWith(systemEffectsStatus: status));
      }
    } catch (_) {}
  }

  Future<void> refreshSystemEffectsStatus() async {
    try {
      final result = await AudioEffectsChannel().detectSystemEffects();
      final status = result['status'] as String? ?? 'unknown';
      final bundles =
          (result['detectedBundles'] as List<dynamic>?)?.cast<String>() ?? [];
      if (!isClosed) {
        safeEmit(state.copyWith(
          systemEffectsStatus: status,
          systemEffectsBundles: bundles,
        ));
      }
    } catch (_) {}
  }

  Future<void> setBluetoothLatencyOffsetMs(int offsetMs) async {
    final clamped = offsetMs.clamp(0, 500);
    safeEmit(state.copyWith(bluetoothLatencyOffsetMs: clamped));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.bluetoothLatencyOffsetMs, clamped);
  }

  /// Toggles per-session audio telemetry. The logger reads this flag on every
  /// call, so disabling takes effect immediately with no re-wiring.
  Future<void> setSessionLogEnabled(bool enabled) async {
    safeEmit(state.copyWith(sessionLogEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.audioSessionLogEnabled, enabled);
  }

  /// Opt-in per-track output-format negotiation. Off by default so the manual
  /// device-global output format is untouched unless the user asks for it.
  Future<void> setOutputFormatNegotiationEnabled(bool enabled) async {
    safeEmit(state.copyWith(outputFormatNegotiationEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.outputFormatNegotiationEnabled, enabled);
  }

  /// Opt-in AAudio Direct output (bit-perfect; the DSP processor chain is
  /// bypassed). Persisted here and pushed to every player by the player
  /// layer; takes effect for newly built sinks.
  Future<void> setAaudioOutputEnabled(bool enabled) async {
    safeEmit(state.copyWith(aaudioOutputEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.aaudioOutputEnabled, enabled);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setAaudioOutputEnabled(
          enabled,
          preferExclusive: state.aaudioPreferExclusive,
          targetBufferMs: state.aaudioTargetBufferMs,
        );
      }
    } catch (_) {
      // Player not available yet; boot/observer push covers it.
    }
  }

  /// Resampler quality (0=Fast/linear, 1=Standard, 2=High, 3=Ultra).
  Future<void> setSincResamplerQuality(int quality) async {
    final clamped = quality.clamp(0, 3);
    safeEmit(state.copyWith(sincResamplerQuality: clamped));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.sincResamplerQuality, clamped);
    await AudioEffectsChannel().setSincResamplerQuality(clamped);
  }

  /// BPM-synced crossfade toggle. Pushed straight to the crossfade manager.
  Future<void> setBpmSyncCrossfadeEnabled(bool enabled) async {
    safeEmit(state.copyWith(bpmSyncCrossfadeEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.bpmSyncCrossfadeEnabled, enabled);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setBpmSyncCrossfadeEnabled(enabled);
      }
    } catch (_) {
      // Player not available yet; boot restore covers it.
    }
  }

  /// Whether the AAudio stream should attempt EXCLUSIVE sharing first.  /// Whether the AAudio stream should attempt EXCLUSIVE sharing first.
  Future<void> setAaudioPreferExclusive(bool value) async {
    safeEmit(state.copyWith(aaudioPreferExclusive: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.aaudioPreferExclusive, value);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setAaudioOutputEnabled(
          state.aaudioOutputEnabled,
          preferExclusive: value,
          targetBufferMs: state.aaudioTargetBufferMs,
        );
      }
    } catch (_) {
      // Player not available yet; boot/observer push covers it.
    }
  }

  /// Target stream buffer capacity for the AAudio path (20-1000 ms).
  /// Re-pushed to running players so it applies without toggling output.
  Future<void> setAaudioTargetBufferMs(int ms) async {
    final clamped = ms.clamp(20, 1000);
    safeEmit(state.copyWith(aaudioTargetBufferMs: clamped));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.aaudioTargetBufferMs, clamped);
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setAaudioOutputEnabled(
          state.aaudioOutputEnabled,
          preferExclusive: state.aaudioPreferExclusive,
          targetBufferMs: clamped,
        );
      }
    } catch (_) {
      // Player not available yet; boot/observer push covers it.
    }
  }

  /// Opt-in 24/32-bit float DSP path. Off by default: with the flag off the
  /// vendored Android fork builds the same 16-bit sink as before. When on, the
  /// preference is persisted here and pushed to every player by the player
  /// layer's settings observer (and restored on boot by the audio handler).
  Future<void> setFloatOutputEnabled(bool enabled) async {
    safeEmit(state.copyWith(floatOutputEnabled: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.floatOutputEnabled, enabled);
    // Best-effort immediate push; the player layer also observes the state.
    try {
      if (getIt.isRegistered<PulsrAudioHandler>()) {
        await getIt<PulsrAudioHandler>().setFloatOutputEnabled(enabled);
      }
    } catch (_) {
      // Player not available yet; boot/observer push covers it.
    }
  }

  // ── F3/F4/F7/F8/F9/F10 ──────────────────────────────────────────────
  Future<void> setHedgedResolutionEnabled(bool v) async {
    safeEmit(state.copyWith(hedgedResolutionEnabled: v));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.hedgedResolutionEnabled, v);
  }

  Future<void> setAdaptiveQualityEnabled(bool v) async {
    safeEmit(state.copyWith(adaptiveQualityEnabled: v));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.adaptiveQualityEnabled, v);
  }

  Future<void> setDuckingMode(String mode) async {
    safeEmit(state.copyWith(duckingMode: mode));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.duckingMode, mode);
  }

  Future<void> setDuckingLevel(double level) async {
    final clamped = level.clamp(0.05, 1.0);
    safeEmit(state.copyWith(duckingLevel: clamped));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(PrefsKeys.duckingLevel, clamped);
  }

  Future<void> setMultiOutputMode(String mode) async {
    safeEmit(state.copyWith(multiOutputMode: mode));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.multiOutputMode, mode);
  }

  Future<void> setDspSnapshotEnabled(bool v) async {
    safeEmit(state.copyWith(dspSnapshotEnabled: v));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.dspSnapshotEnabled, v);
  }

  Future<void> setSilenceSkipSensitivity(int v) async {
    final clamped = v.clamp(0, 100);
    safeEmit(state.copyWith(silenceSkipSensitivity: clamped));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.silenceSkipSensitivity, clamped);
  }

  /// F5: Bluetooth latency auto-calibration. Uses the codec latency table
  /// plus optional probe samples, then persists the winning offset.
  Future<int> autoCalibrateBluetoothLatency({Future<int> Function()? probe}) async {
    final codec = state.currentOutputDevice?.btCodecName;
    int codecEst = 180;
    try {
      const table = {
        'sbc': 220, 'aac': 200, 'aptx': 150, 'ldac': 250,
        'lc3': 60, 'opus': 100, 'lhdc': 180,
      };
      if (codec != null && codec.isNotEmpty) {
        final key = codec.toLowerCase();
        for (final e in table.entries) {
          if (key.contains(e.key)) {
            codecEst = e.value;
            break;
          }
        }
      }
    } catch (_) {}
    var combined = codecEst;
    if (probe != null) {
      final vals = <int>[];
      for (var i = 0; i < 5; i++) {
        try {
          final v = await probe();
          if (v >= 0 && v <= 1000) vals.add(v);
        } catch (_) {}
      }
      if (vals.isNotEmpty) {
        vals.sort();
        final trimmed =
            vals.length >= 4 ? vals.sublist(1, vals.length - 1) : vals;
        final avg = (trimmed.reduce((a, b) => a + b) / trimmed.length).round();
        combined = (codecEst * 0.6 + avg * 0.4).round();
      }
    }
    final clamped = combined.clamp(0, 500);
    await setBluetoothLatencyOffsetMs(clamped);
    return clamped;
  }

  /// Applies the "Maximum Quality" audiophile preset:
  /// Bit-perfect mode enabled, all DSP/EQ/ReplayGain/crossfade bypassed, gapless active.
  Future<void> applyMaximumQualityPreset() async {
    await setBitPerfectOutput(true);
    await setBypassDspOnBitPerfect(true);
    await setReplayGainMode(ReplayGainMode.off);
    await setGapless(true);
  }

  /// Applies the "Smooth Playback" preset:
  /// Standard crossfade, auto ReplayGain, adaptive buffering.
  Future<void> applySmoothPlaybackPreset() async {
    await setBitPerfectOutput(false);
    await setReplayGainMode(ReplayGainMode.auto);
    await setCrossfade(4.0);
  }

  /// Applies the "Poor Network" preset:
  /// Conservative data usage, zero crossfade, lower bitrate.
  Future<void> applyPoorNetworkPreset() async {
    await setCrossfade(0.0);
    await setGapless(false);
    await setStreamingQuality(YtmAudioQuality.low);
  }
}
