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
import '../../../data/audio/mqa_decoder_helper.dart';
import '../../../core/di/injection.dart';
import '../../../core/network/app_http_overrides.dart';
import '../../../core/network/proxy_config.dart';
import '../../../core/services/hires_audio_service.dart';
import '../../../core/services/theme_scheduler_service.dart';
import '../../../core/utils/error_logger.dart';
import '../../../data/audio/audio_effects_channel.dart';
import '../../../data/audio/audio_handler.dart';
import '../../../data/audio/dsd_decoder_helper.dart';
import '../../../data/db/app_database.dart';
import '../../../data/audio/equalizer_manager.dart';
import '../../../data/audio/multi_output_router.dart';
import '../../../data/scanner/media_scanner_service.dart';
import '../../../domain/repositories/music_repository_interface.dart';
import '../../../core/constants/audio_feature_info.dart';
import '../../player/presentation/widgets/audio_visualizer.dart';
import 'proxy_endpoint_validator.dart';
import 'settings_state.dart';
import 'theme_schedule_controller.dart';
part 'settings_proxy_actions.dart';
part 'settings_audio_actions.dart';

@singleton
class SettingsCubit extends PulsrCubit<SettingsState>
    with SettingsProxyActions, SettingsAudioActions {
  final MediaScannerService _scannerService;
  @override
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
  static const String _keyLiquidGlassTint = 'setting_liquid_glass_tint';
  static const String _keyLanguageCode = PrefsKeys.languageCode;
  static const String _keyCustomAccent = 'setting_custom_accent';
  static const String _keyCustomThemeRadius = 'setting_custom_theme_radius';
  static const String _keyCustomThemeGlow = 'setting_custom_theme_glow';
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

  @override
  final FlutterSecureStorage _secureStorage;
  ThemeScheduleController? _themeScheduleController;
  @override
  String _proxyPassword = '';

  /// Set by the proxy setters, cleared when a load starts. Lets a load that is
  /// still in flight know its on-disk snapshot is stale and must not clobber
  /// the edit the user just made.
  @override
  bool _proxyDirty = false;

  @override
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

  /// Theme-schedule ownership lives in [ThemeScheduleController] (god-object
  /// split): the cubit only gates on [SettingsState.autoThemeByTime] and
  /// applies the resulting theme mode. The callback never overrides a manual
  /// theme mode unless the user has opted into scheduled switching.
  void _initThemeScheduler() {
    try {
      final scheduler = getIt.isRegistered<ThemeSchedulerService>()
          ? getIt<ThemeSchedulerService>()
          : ThemeSchedulerService();
      _themeScheduleController = ThemeScheduleController(
        scheduler: scheduler,
        isAutoEnabled: () => !isClosed && state.autoThemeByTime,
        onNightChanged: (isNight) {
          if (isClosed || !state.autoThemeByTime) return;
          setThemeMode(isNight ? AppThemeMode.dark : AppThemeMode.light);
        },
      );
      unawaited(_themeScheduleController!.init());
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to start theme scheduler',
        error: e,
        stackTrace: st,
        category: 'SettingsCubit',
      );
    }
  }

  /// Persists and applies a new dark-hours window. Restarts the scheduler so
  /// the change is reflected immediately when scheduled theming is on.
  Future<void> setThemeScheduleHours({required int start, required int end}) =>
      _themeScheduleController?.setHours(start: start, end: end) ??
      Future.value();

  @override
  Future<void> close() {
    _themeScheduleController?.dispose();
    _themeScheduleController = null;
    return super.close();
  }

  void clearError() {
    safeEmit(state.copyWith(errorMessage: null));
  }

  Future<void> reloadSettings() async {
    await _loadPreferences();
  }


  Future<void> _loadPreferences() async {
    _proxyDirty = false;
    try {
      final results = await Future.wait([
        SharedPreferences.getInstance(),
        _safeSecureRead(_keyProxyPasswordSecure),
      ]);
      final prefs = results[0] as SharedPreferences;
      String proxyPassword = (results[1] as String?) ?? '';

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

      // Remote yt-dlp backend was removed: purge any legacy backend prefs so
      // upgraded installs don't carry stale configuration forward. Keep the
      // secure-storage delete independent so its failure (e.g. no keystore)
      // can never block the SharedPreferences cleanup.
      try {
        await _secureStorage.delete(key: 'xdm_backend_token_secure');
      } catch (_) {}
      try {
        await prefs.remove(PrefsKeys.ytdlpBackendToken);
        await prefs.remove(PrefsKeys.ytdlpBackendEnabled);
        await prefs.remove(PrefsKeys.ytdlpBackendUrl);
        await prefs.remove(PrefsKeys.extractorEngine);
        await prefs.remove(PrefsKeys.syncCookiesToBackend);
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
          prefs.getBool(PrefsKeys.followTrackSampleRate) ?? true;
      // Default to PCM when unset or unrecognized. DoP is never auto-enabled.
      final dsdOutputModeLoaded = DsdOutputMode.values.firstWhere(
        (e) =>
            e.name == (prefs.getString(PrefsKeys.dsdOutputMode) ?? 'pcm'),
        orElse: () => DsdOutputMode.pcm,
      );
      // Default to Normal so existing users land on the curated experience.
      final experienceModeLoaded = ExperienceMode.fromName(
          prefs.getString(PrefsKeys.experienceMode));

      final loadedCrossfade =
          prefs.getDouble(_keyCrossfade) ?? state.crossfadeSeconds;
      final loadedBitPerfect =
          prefs.getBool(PrefsKeys.bitPerfectOutput) ?? state.bitPerfectOutput;
      // Bit-perfect cannot run with crossfade (it would alter the bitstream), so
      // a legacy persisted pair is reconciled to crossfade off on load instead of
      // letting the engine overlap tracks under a bit-perfect sink.
      final effectiveCrossfade =
          (loadedBitPerfect && loadedCrossfade > 0.01) ? 0.0 : loadedCrossfade;
      if (effectiveCrossfade != loadedCrossfade) {
        try {
          await prefs.setDouble(_keyCrossfade, effectiveCrossfade);
        } catch (_) {}
      }

      final newState = state.copyWith(
        // Crossfade > 0 forces gapless OFF (they are mutually exclusive), even
        // if legacy prefs stored both on.
        gaplessPlayback: (effectiveCrossfade > 0.01)
            ? false
            : (prefs.getBool(_keyGapless) ?? state.gaplessPlayback),
        crossfadeSeconds: effectiveCrossfade,
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
        reduceMotion: prefs.getBool('setting_reduce_motion') ?? state.reduceMotion,
        liquidGlassTint:
            prefs.getDouble(_keyLiquidGlassTint) ?? state.liquidGlassTint,
        languageCode: prefs.getString(_keyLanguageCode) ?? state.languageCode,
        customAccentColorValue: customAccentValue,
        customThemeRadius:
            prefs.getDouble(_keyCustomThemeRadius) ?? state.customThemeRadius,
        customThemeGlow:
            prefs.getBool(_keyCustomThemeGlow) ?? state.customThemeGlow,
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
            true,
        floatOutputEnabled:
            prefs.getBool(PrefsKeys.floatOutputEnabled) ?? true,
        aaudioOutputEnabled:
            prefs.getBool(PrefsKeys.aaudioOutputEnabled) ?? false,
        dvcEnabled: prefs.getBool(PrefsKeys.dvcEnabled) ?? false,
        usbHardwareVolumeEnabled:
            prefs.getBool(PrefsKeys.usbHardwareVolumeEnabled) ?? false,
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
      // MQA hook wiring (orphan 20-01): the decoder hook previously defaulted
      // ON with no owner; the preference now owns it.
      await loadMqaDecodingPreference();
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
      _themeScheduleController?.start();
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to load settings preferences from SharedPreferences',
        error: e,
        stackTrace: st,
        category: 'SettingsCubit',
      );
    }
  }

  @override
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

  @override
  Future<void> setCrossfade(double seconds) async {
    final clamped = seconds.clamp(0.0, 12.0);
    final bitPerfectBlock = AudioConflicts.crossfadeBlockedByBitPerfect(
      bitPerfectOutput: state.bitPerfectOutput,
      bypassDspOnBitPerfect: state.bypassDspOnBitPerfect,
      device: state.currentOutputDevice,
      aaudioEnabled: state.aaudioOutputEnabled,
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
      _themeScheduleController?.start();
    } else {
      _themeScheduleController?.stop();
    }
  }

  Future<void> setHighContrast(bool value) async {
    safeEmit(state.copyWith(highContrast: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHighContrast, value);
  }

  Future<void> setLiquidGlassTint(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    safeEmit(state.copyWith(liquidGlassTint: clamped));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyLiquidGlassTint, clamped);
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

  Future<void> setCustomThemeRadius(double radius) async {
    final clamped = radius.clamp(0.0, 48.0);
    safeEmit(state.copyWith(customThemeRadius: clamped));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyCustomThemeRadius, clamped);
  }

  Future<void> setCustomThemeGlow(bool enabled) async {
    safeEmit(state.copyWith(customThemeGlow: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCustomThemeGlow, enabled);
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


  // --- Proxy Settings Actions ---


  /// Tests connectivity through the provided or current proxy config.
  Future<({bool success, int latencyMs, String? error})> testProxyConnection([
    ProxyConfig? config,
  ]) async {
    final configToTest = config ?? activeProxyConfig;
    return AppHttpOverrides.instance.testConnection(configToTest: configToTest);
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

  /// Rebuilds the FTS search index on demand. Resets the per-session retry
  /// budget and reports success so the UI can confirm. A no-op if the database
  /// is not available (e.g. tests).
  Future<bool> rebuildSearchIndex() async {
    try {
      if (!getIt.isRegistered<AppDatabase>()) return false;
      return await getIt<AppDatabase>().repairFtsIndex(force: true);
    } catch (e, st) {
      ErrorLogger.log('Failed to rebuild search index',
          error: e, stackTrace: st, category: 'SettingsCubit');
      return false;
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


  /// MQA approximate-unfold toggle (orphan 20-01 wiring, tranche 5). Drives
  /// [MqaDecoderHelper.isMqaEnabled], which [FormatAwareDecoder] consults
  /// before running the approximate first-unfold. Defaults ON to preserve
  /// long-standing behaviour (hook defaulted to true via `?? true`).
  static bool mqaEnabledCache = true;
  static bool get isMqaDecodingEnabled => mqaEnabledCache;


  // ── Bluetooth codec control ──────────────────────────────────────────────


}
