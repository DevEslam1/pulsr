import 'dart:async';
import 'dart:convert';
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
import '../../../domain/services/hires_audio_service.dart';
import '../../../data/services/xdm_backend_service.dart';
import '../../../core/utils/error_logger.dart';
import '../../../data/audio/audio_effects_channel.dart';
import '../../../data/scanner/media_scanner_service.dart';
import '../../../domain/models/audio_output_info.dart';
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
  static const String _keyAutoHideSystemMedia =
      'setting_auto_hide_system_media';
  static const String _keyDynamicTheme = 'setting_dynamic_theme';
  static const String _keyThemeColorSource = 'setting_theme_color_source';
  static const String _keyResumeAfterInterruption =
      'setting_resume_after_interruption';
  static const String _keyWaveformSeekBar = 'setting_waveform_seek_bar';
  static const String _keyThemeMode = 'setting_theme_mode';
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

  final FlutterSecureStorage _secureStorage;
  String _proxyPassword = '';

  ProxyConfig get activeProxyConfig =>
      state.proxyConfig.copyWith(password: _proxyPassword);

  Future<String> getProxyPassword() async {
    if (_proxyPassword.isNotEmpty) return _proxyPassword;
    try {
      final pass = await _secureStorage.read(key: _keyProxyPasswordSecure);
      if (pass != null) {
        _proxyPassword = pass;
      }
    } catch (e, st) {
      ErrorLogger.log('getProxyPassword failed', error: e, stackTrace: st, category: 'SettingsCubit');
    }
    return _proxyPassword;
  }

  SettingsCubit({
    required MediaScannerService scannerService,
    HiResAudioService? hiResAudioService,
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
  }) : _scannerService = scannerService,
       _secureStorage = secureStorage,
       _hiResAudioService =
           hiResAudioService ??
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
            targetSampleRate:
                device.targetSampleRate != 0
                    ? device.targetSampleRate
                    : savedSampleRate,
            targetBitDepth:
                device.targetBitDepth != 0
                    ? device.targetBitDepth
                    : savedBitDepth,
            isBitPerfectActive:
                device.isBitPerfectActive ||
                (state.bitPerfectOutput && device.isUsbDac),
          ),
        ),
      );
    });
    _loadPreferences();
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
    try {
      await _proxyChannel.invokeMethod('setProxy', config.toMap());
    } catch (e) {
      debugPrint('[SettingsCubit] Failed to sync proxy to native channel: $e');
    }
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
    try {
      final results = await Future.wait([
        SharedPreferences.getInstance(),
        _safeSecureRead(_keyProxyPasswordSecure),
        _safeSecureRead('xdm_backend_token_secure'),
      ]);
      final prefs = results[0] as SharedPreferences;
      String proxyPassword = (results[1] as String?) ?? '';
      String xdmToken = (results[2] as String?) ?? '';

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

      final miniPlayerSwipeLeftStr =
          prefs.getString(_keyMiniPlayerSwipeLeft) ??
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

      final nowPlayingDoubleTapStr =
          prefs.getString(_keyNowPlayingDoubleTap) ??
          NowPlayingDoubleTapAction.toggleFavorite.name;
      final nowPlayingDoubleTap = NowPlayingDoubleTapAction.values.firstWhere(
        (e) => e.name == nowPlayingDoubleTapStr,
        orElse: () => NowPlayingDoubleTapAction.toggleFavorite,
      );

      final nowPlayingArtworkSwipeStr =
          prefs.getString(_keyNowPlayingArtworkSwipe) ??
          NowPlayingArtworkSwipeAction.nextPrev.name;
      final nowPlayingArtworkSwipe = NowPlayingArtworkSwipeAction.values
          .firstWhere(
            (e) => e.name == nowPlayingArtworkSwipeStr,
            orElse: () => NowPlayingArtworkSwipeAction.nextPrev,
          );

      final replayGainModeStr =
          prefs.getString(_keyReplayGainMode) ?? ReplayGainMode.track.name;
      final replayGainMode = ReplayGainMode.values.firstWhere(
        (e) => e.name == replayGainModeStr,
        orElse: () => ReplayGainMode.track,
      );
      final replayGainPreampWithRg =
          prefs.getDouble(_keyReplayGainPreampWithRg) ?? 0.0;
      final replayGainPreampWithoutRg =
          prefs.getDouble(_keyReplayGainPreampWithoutRg) ?? -3.0;

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
      final proxyPort = prefs.getInt(_keyProxyPort) ?? 8080;
      final proxyUsername = prefs.getString(_keyProxyUsername) ?? '';

      // Legacy proxy password migration already handled above (lines 164-186)
      // No second migration needed.

      if (xdmToken.isEmpty) {
        final legacyToken =
            prefs.getString(PrefsKeys.ytdlpBackendToken)?.trim();
        if (legacyToken != null && legacyToken.isNotEmpty) {
          xdmToken = legacyToken;
          try {
            await _secureStorage.write(
              key: 'xdm_backend_token_secure',
              value: legacyToken,
            );
            await prefs.remove(PrefsKeys.ytdlpBackendToken);
          } catch (e, st) {
            ErrorLogger.log('settings_cubit failed', error: e, stackTrace: st, category: 'SettingsCubit');
          }
        } else {
          xdmToken = XdmBackendService.defaultApiToken;
        }
      }

      final proxyBypassHosts =
          prefs.getString(_keyProxyBypassHosts) ?? 'localhost, 127.0.0.1';

      List<ProxyEntry> proxyList = [];
      final proxyListRaw = prefs.getString(_keyProxyList);
      if (proxyListRaw != null && proxyListRaw.isNotEmpty) {
        try {
          final decoded = jsonDecode(proxyListRaw) as List<dynamic>;
          proxyList =
              decoded
                  .map((e) => ProxyEntry.fromMap(e as Map<String, dynamic>))
                  .where((e) => e.isValid)
                  .toList();
        } catch (e, st) {
          ErrorLogger.log('where failed', error: e, stackTrace: st, category: 'SettingsCubit');
        }
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
        themeColorSource =
            (prefs.getBool(_keyDynamicTheme) ?? true)
                ? ThemeColorSource.artwork
                : ThemeColorSource.custom;
      } else {
        themeColorSource = ThemeColorSource.artwork;
      }

      final newState = state.copyWith(
        gaplessPlayback: prefs.getBool(_keyGapless) ?? state.gaplessPlayback,
        crossfadeSeconds:
            prefs.getDouble(_keyCrossfade) ?? state.crossfadeSeconds,
        minDurationSec: prefs.getInt(_keyMinDuration) ?? state.minDurationSec,
        autoHideSystemMedia:
            prefs.getBool(_keyAutoHideSystemMedia) ?? state.autoHideSystemMedia,
        themeColorSource: themeColorSource,
        resumeAfterInterruption:
            prefs.getBool(_keyResumeAfterInterruption) ??
            state.resumeAfterInterruption,
        waveformSeekBarEnabled:
            prefs.getBool(_keyWaveformSeekBar) ?? state.waveformSeekBarEnabled,
        themeMode: themeMode,
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
        extractorEngine: ExtractorEngine.values.firstWhere(
          (e) => e.name == prefs.getString(PrefsKeys.extractorEngine),
          orElse: () => ExtractorEngine.auto,
        ),
        ytdlpBackendEnabled:
            prefs.getBool(PrefsKeys.ytdlpBackendEnabled) ?? false,
        ytdlpBackendUrl:
            prefs.getString(PrefsKeys.ytdlpBackendUrl) ?? state.ytdlpBackendUrl,
        ytdlpBackendToken:
            xdmToken.isNotEmpty ? xdmToken : state.ytdlpBackendToken,
        syncCookiesToBackend:
            prefs.getBool(PrefsKeys.syncCookiesToBackend) ?? false,
        bitPerfectOutput:
            prefs.getBool(PrefsKeys.bitPerfectOutput) ?? state.bitPerfectOutput,
        bypassDspOnBitPerfect:
            prefs.getBool(PrefsKeys.bypassDspOnBitPerfect) ??
            state.bypassDspOnBitPerfect,
        currentOutputDevice: _hiResAudioService.currentOutputInfo,
        crossfeedEnabled:
            prefs.getBool(PrefsKeys.crossfeedEnabled) ?? state.crossfeedEnabled,
        crossfeedDelayUs:
            prefs.getDouble(PrefsKeys.crossfeedDelayUs) ??
            state.crossfeedDelayUs,
        crossfeedFeedDb:
            prefs.getDouble(PrefsKeys.crossfeedFeedDb) ?? state.crossfeedFeedDb,
        limiterEnabled:
            prefs.getBool(PrefsKeys.lookaheadLimiterEnabled) ??
            state.limiterEnabled,
        limiterLookaheadMs:
            prefs.getDouble('setting_lookahead_limiter_lookahead_ms') ??
            state.limiterLookaheadMs,
        limiterThresholdDb:
            prefs.getDouble(PrefsKeys.lookaheadLimiterThresholdDb) ??
            state.limiterThresholdDb,
        limiterReleaseMs:
            prefs.getDouble(PrefsKeys.lookaheadLimiterReleaseMs) ??
            state.limiterReleaseMs,
        reverbEnabled:
            prefs.getBool(PrefsKeys.convolutionReverbEnabled) ??
            state.reverbEnabled,
        reverbPreset:
            prefs.getInt(PrefsKeys.convolutionReverbPreset) ??
            state.reverbPreset,
        reverbWetDry:
            prefs.getDouble(PrefsKeys.convolutionReverbWetDry) ??
            state.reverbWetDry,
        stereoBalance:
            prefs.getDouble(PrefsKeys.stereoBalance) ?? state.stereoBalance,
        monoMix: prefs.getBool(PrefsKeys.monoMix) ?? state.monoMix,
        sincResamplerEnabled:
            prefs.getBool(PrefsKeys.sincResamplerEnabled) ??
            state.sincResamplerEnabled,
        dspPreference:
            prefs.getString(_keyDspPreference) ?? state.dspPreference,
        systemEffectsPolicy:
            prefs.getString(PrefsKeys.systemEffectsPolicy) ?? state.systemEffectsPolicy,
        bluetoothLatencyOffsetMs:
            prefs.getInt(PrefsKeys.bluetoothLatencyOffsetMs) ?? state.bluetoothLatencyOffsetMs,
      );

      _proxyPassword = proxyPassword;
      await AudioEffectsChannel().setDspPreference(newState.dspPreference);
      try {
        await AudioEffectsChannel().setSystemEffectsPolicy(
          newState.systemEffectsPolicy,
          isHiResOrBitPerfect: newState.bitPerfectOutput,
        );
      } catch (e, st) {
        ErrorLogger.log('settings_cubit failed', error: e, stackTrace: st, category: 'SettingsCubit');
      }
      if (newState.bitPerfectOutput) {
        await _hiResAudioService.setBitPerfectMode(true);
      }
      if (newState.bitPerfectOutput && newState.bypassDspOnBitPerfect) {
        // Re-assert the DSP-bypass policy at boot: without this the Kotlin
        // effects plugin keeps its default (bypass off) after a restart and
        // the saved bit-perfect conflict rule is not enforced this session.
        await AudioEffectsChannel().setBypassDspForBitPerfect(true);
      }
      if (!isClosed) {
        // FIX: fragile merge removed. The previous conditional merged current state's
        // proxy fields when hardware output stream fired before prefs load finished,
        // causing race-dependent lost writes. prefs-loaded newState is now the
        // single source of truth; hardware stream (HiRes) only mutates outputDevice
        // which we preserve below.
        // FIX(race): _loadPreferences is async from ctor — user/test may have
        // mutated proxy state before it finishes. Don't wipe non-empty
        // in-memory proxy edits with empty prefs defaults.
        final currentDevice = state.currentOutputDevice;
        final keepProxyList = state.proxyList.isNotEmpty && proxyList.isEmpty
            ? state.proxyList
            : proxyList;
        final keepProxyHost = state.proxyHost.isNotEmpty && proxyHost.isEmpty
            ? state.proxyHost
            : proxyHost;
        final keepProxyPort = state.proxyHost.isNotEmpty && proxyHost.isEmpty
            ? state.proxyPort
            : proxyPort;
        final keepProxyUsername =
            state.proxyHost.isNotEmpty && proxyHost.isEmpty
                ? state.proxyUsername
                : proxyUsername;
        final keepProxyEnabled =
            state.proxyHost.isNotEmpty && proxyHost.isEmpty
                ? state.proxyEnabled
                : proxyEnabled;
        safeEmit(newState.copyWith(
          // Preserve hardware-derived output device if it arrived early and has richer data
          currentOutputDevice: (currentDevice != null && currentDevice.availableDevices.isNotEmpty && newState.currentOutputDevice?.availableDevices.isEmpty == true)
              ? currentDevice
              : newState.currentOutputDevice,
          proxyList: keepProxyList,
          proxyHost: keepProxyHost,
          proxyPort: keepProxyPort,
          proxyUsername: keepProxyUsername,
          proxyEnabled: keepProxyEnabled,
        ));
      }
      final savedSampleRate = prefs.getInt('target_output_sample_rate') ?? 0;
      final savedBitDepth = prefs.getInt('target_output_bit_depth') ?? 0;
      if (savedSampleRate > 0 || savedBitDepth > 0) {
        await _hiResAudioService.setTargetOutputFormat(
          sampleRate: savedSampleRate,
          bitDepth: savedBitDepth,
        );
      }
      await _syncProxySettings(activeProxyConfig);
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
    if (value && state.crossfadeSeconds > 0.0) {
      safeEmit(
        state.copyWith(
          gaplessPlayback: true,
          crossfadeSeconds: 0.0,
          errorMessage:
              AudioConflicts.gaplessBlockedByCrossfade(
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
    if (clamped > 0.0 && state.gaplessPlayback) {
      // Crossfade needs gapless OFF — auto-disable gapless
      safeEmit(
        state.copyWith(
          crossfadeSeconds: clamped,
          gaplessPlayback: false,
          errorMessage:
              AudioConflicts.crossfadeBlockedByGapless(true) ??
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

  Future<void> setAutoHideSystemMedia(bool value) async {
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

  Future<void> setThemeMode(AppThemeMode mode) async {
    safeEmit(state.copyWith(themeMode: mode));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, mode.name);
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
    } catch (e, st) {
      ErrorLogger.log('toARGB32 failed, using fallback', error: e, stackTrace: st, category: 'SettingsCubit');
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
    final trimmedHost = host.trim();
    if (enabled) {
      if (trimmedHost.isEmpty) {
        safeEmit(state.copyWith(errorMessage: 'Proxy host cannot be empty'));
        return;
      }
      // FIX: delegate host validation to Uri + strict regex to avoid junk like ::::: matching IPv6 pattern.
      // We try Uri parsing first, then strict IPv4/hostname/IPv6 checks.
      bool isValidHost = false;
      // Try Uri/host validation
      try {
        final uri = Uri.tryParse('http://$trimmedHost');
        final hostPart = uri?.host ?? '';
        if (hostPart.isNotEmpty && hostPart == trimmedHost.replaceAll(RegExp(r'^\[|\]$'), '')) {
          // Uri parsed successfully and host matches (handles brackets for IPv6)
          isValidHost = true;
        }
      } catch (e, st) {
        ErrorLogger.log('setProxySettings failed', error: e, stackTrace: st, category: 'SettingsCubit');
      }
      if (!isValidHost) {
        final isIPv4 = RegExp(r'^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$').hasMatch(trimmedHost);
        // Stricter IPv6: at least 2 colons, only hex + colons, no 4+ consecutive colons
        final isIPv6 = !trimmedHost.contains('::::') &&
            RegExp(r'^[0-9a-fA-F:]+$').hasMatch(trimmedHost) &&
            trimmedHost.contains(':') &&
            (trimmedHost == '::1' || trimmedHost.startsWith('fe80:') || RegExp(r'^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$').hasMatch(trimmedHost));
        final isHostname = RegExp(r'^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$').hasMatch(trimmedHost);
        final isLocalhost = trimmedHost == 'localhost' || trimmedHost == '127.0.0.1';
        isValidHost = isIPv4 || isIPv6 || isHostname || isLocalhost;
      }
      if (!isValidHost) {
        safeEmit(state.copyWith(errorMessage: 'Invalid proxy host format'));
        return;
      }
      if (port < 1 || port > 65535) {
        safeEmit(state.copyWith(errorMessage: 'Proxy port must be between 1 and 65535'));
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
    } catch (e, st) {
      ErrorLogger.log('setProxySettings failed', error: e, stackTrace: st, category: 'SettingsCubit');
    }
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

  Future<void> _saveProxyList(List<ProxyEntry> list) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = list.map((e) => e.toMap()).toList();
    await prefs.setString(_keyProxyList, jsonEncode(jsonList));
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
    final currentList = List<ProxyEntry>.from(state.proxyList);

    for (int i = 0; i < currentList.length; i += 5) {
      final end = math.min(i + 5, currentList.length);
      for (int j = i; j < end; j++) {
        currentList[j] = currentList[j].copyWith(isTesting: true);
      }
      safeEmit(state.copyWith(proxyList: List.from(currentList)));

      await Future.wait(
        List.generate(end - i, (offset) async {
          final index = i + offset;
          final entry = currentList[index];
          final result = await AppHttpOverrides.instance.testConnection(
            configToTest: entry.toProxyConfig(enabled: true),
            timeout: const Duration(seconds: 10),
          );
          currentList[index] = currentList[index].copyWith(
            isTesting: false,
            isWorking: result.success,
            latencyMs: result.latencyMs,
            lastError: result.error,
          );
        }),
      );

      safeEmit(state.copyWith(proxyList: List.from(currentList)));
    }

    safeEmit(state.copyWith(isTestingAllProxies: false));
    await _saveProxyList(currentList);
  }

  /// Tests a single proxy entry in the pool by its ID.
  Future<void> testSingleProxyEntry(String id) async {
    final index = state.proxyList.indexWhere((e) => e.id == id);
    if (index < 0) return;

    final entry = state.proxyList[index];
    final updatedList = List<ProxyEntry>.from(state.proxyList);
    updatedList[index] = entry.copyWith(isTesting: true);
    safeEmit(state.copyWith(proxyList: updatedList));

    final result = await AppHttpOverrides.instance.testConnection(
      configToTest: entry.toProxyConfig(enabled: true),
      timeout: const Duration(seconds: 10),
    );

    updatedList[index] = updatedList[index].copyWith(
      isTesting: false,
      isWorking: result.success,
      latencyMs: result.latencyMs,
      lastError: result.error,
    );
    safeEmit(state.copyWith(proxyList: updatedList));
    await _saveProxyList(updatedList);
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.extractorEngine, engine.name);
    final isBackendActive = engine != ExtractorEngine.onDevice;
    await prefs.setBool(PrefsKeys.ytdlpBackendEnabled, isBackendActive);
    safeEmit(
      state.copyWith(
        extractorEngine: engine,
        ytdlpBackendEnabled: isBackendActive,
      ),
    );
  }

  Future<void> setYtdlpBackendEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.ytdlpBackendEnabled, enabled);
    final newEngine = enabled ? ExtractorEngine.auto : ExtractorEngine.onDevice;
    await prefs.setString(PrefsKeys.extractorEngine, newEngine.name);
    safeEmit(
      state.copyWith(ytdlpBackendEnabled: enabled, extractorEngine: newEngine),
    );
  }

  Future<void> setYtdlpBackendUrl(String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isNotEmpty) {
      final parsed = Uri.tryParse(cleanUrl);
      if (parsed == null ||
          (!parsed.isScheme('http') && !parsed.isScheme('https')) ||
          parsed.host.isEmpty) {
        safeEmit(
          state.copyWith(
            errorMessage:
                'Invalid backend URL format. Must be http:// or https://',
          ),
        );
        return;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.ytdlpBackendUrl, cleanUrl);
    safeEmit(state.copyWith(ytdlpBackendUrl: cleanUrl, errorMessage: null));
  }

  Future<void> setYtdlpBackendToken(String token) async {
    final cleanToken = token.trim();
    try {
      if (cleanToken.isNotEmpty) {
        await _secureStorage.write(
          key: 'xdm_backend_token_secure',
          value: cleanToken,
        );
      } else {
        await _secureStorage.delete(key: 'xdm_backend_token_secure');
      }
    } catch (e, st) {
      ErrorLogger.log('setYtdlpBackendToken failed', error: e, stackTrace: st, category: 'SettingsCubit');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PrefsKeys.ytdlpBackendToken);
    safeEmit(state.copyWith(ytdlpBackendToken: cleanToken));
  }

  Future<void> setSyncCookiesToBackend(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.syncCookiesToBackend, value);
    safeEmit(state.copyWith(syncCookiesToBackend: value));
  }

  Future<void> testYtdlpBackend() async {
    safeEmit(
      state.copyWith(
        isTestingYtdlpBackend: true,
        ytdlpBackendStatusMessage: null,
      ),
    );
    try {
      final xdm = getIt<XdmBackendService>();
      final health = await xdm.checkHealth(force: true);
      safeEmit(
        state.copyWith(
          isTestingYtdlpBackend: false,
          ytdlpBackendStatusMessage: health.message,
          ytdlpBackendVersion: health.backendVersion,
          ytdlpBackendProxyCount: health.proxyPoolSize,
          ytdlpBackendCircuitState: health.circuitState.name,
        ),
      );
    } catch (e) {
      safeEmit(
        state.copyWith(
          isTestingYtdlpBackend: false,
          ytdlpBackendStatusMessage: 'Error: $e',
        ),
      );
    }
  }

  Future<int> rescanLibrary() async {
    // FIX: re-entrancy guard — startup auto-scan + user tap raced two full
    // MediaStore scans (double DB writes, orphan flaps).
    if (state.isScanning) return 0;
    safeEmit(
      state.copyWith(
        isScanning: true,
        scanResultCount: null,
        errorMessage: null,
      ),
    );
    try {
      final count = await _scannerService.scanDeviceLibrary(
        ignoreShortFiles: state.minDurationSec > 0,
        minDurationSec: state.minDurationSec,
        autoHideSystemMedia: state.autoHideSystemMedia,
      );
      if (isClosed) return count;
      safeEmit(state.copyWith(isScanning: false, scanResultCount: count));
      return count;
    } catch (e) {
      if (isClosed) return 0;
      // Don't leak internals (paths, SQL) to the snackbar.
      safeEmit(state.copyWith(
          isScanning: false,
          errorMessage: 'Library scan failed. Please try again.'));
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
        currentOutputDevice: state.currentOutputDevice?.copyWith(
          isBitPerfectActive: enabled,
        ),
        errorMessage: null,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.bitPerfectOutput, enabled);
    await _hiResAudioService.setBitPerfectMode(enabled);
    // Wire bypass: when bit-perfect enabled and user wants bypass, force DSP off via native
    if (enabled && state.bypassDspOnBitPerfect) {
      try {
        await AudioEffectsChannel().setBypassDspForBitPerfect(true);
      } catch (e, st) {
        ErrorLogger.log('setBitPerfectOutput failed', error: e, stackTrace: st, category: 'SettingsCubit');
      }
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
        await AudioEffectsChannel().setBypassDspForBitPerfect(false);
      } catch (e, st) {
        ErrorLogger.log('setBitPerfectOutput failed', error: e, stackTrace: st, category: 'SettingsCubit');
      }
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
        await AudioEffectsChannel().setBypassDspForBitPerfect(enabled);
      } catch (e, st) {
        ErrorLogger.log('setBypassDspOnBitPerfect failed', error: e, stackTrace: st, category: 'SettingsCubit');
      }
      await refreshOutputDevice();
    }
  }

  Future<void> selectOutputDevice(int deviceId) async {
    if (state.currentOutputDevice != null) {
      final updatedDevices =
          state.currentOutputDevice!.availableDevices.map((d) {
            return AudioDeviceEntry(
              id: d.id,
              name: d.name,
              type: d.type,
              typeName: d.typeName,
              isCurrent: d.id == deviceId,
              sampleRates: d.sampleRates,
              maxBitDepth: d.maxBitDepth,
            );
          }).toList();
      safeEmit(
        state.copyWith(
          currentOutputDevice: state.currentOutputDevice!.copyWith(
            availableDevices: updatedDevices,
          ),
        ),
      );
    }
    await _hiResAudioService.selectOutputDevice(deviceId);
    await refreshOutputDevice();
  }

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
    // FIX: replace magic 500ms with permission-aware poll. The system dialog is
    // async; waiting fixed 500ms raced slow devices. We now poll permission
    // state via refreshOutputDevice with exponential backoff up to ~2s.
    for (int attempt = 0; attempt < 4; attempt++) {
      await Future<void>.delayed(Duration(milliseconds: 300 * (1 << attempt) ~/ 2 + 200));
      await refreshOutputDevice();
      // If device info shows Bluetooth available, break early.
      final dev = state.currentOutputDevice;
      if (dev != null && dev.availableDevices.any((d) => d.typeName.toLowerCase().contains('bluetooth'))) {
        break;
      }
      if (attempt == 3) break;
    }
  }

  /// Opens Android Developer Options directly to the Bluetooth Audio Codec page.
  Future<void> openBluetoothDevOptions() async {
    await _hiResAudioService.openBluetoothDevOptions();
  }

  Future<void> refreshOutputDevice() async {
    final info = await _hiResAudioService.getAudioOutputInfo();
    final previous = state.currentOutputDevice;
    final savedSampleRate =
        (previous?.targetSampleRate != null && previous!.targetSampleRate > 0)
            ? previous.targetSampleRate
            : 0;
    final savedBitDepth =
        (previous?.targetBitDepth != null && previous!.targetBitDepth > 0)
            ? previous.targetBitDepth
            : 0;
    final isBitPerfect = state.bitPerfectOutput;

    if (isClosed) return;
    safeEmit(
      state.copyWith(
        currentOutputDevice: info.copyWith(
          targetSampleRate:
              info.targetSampleRate != 0
                  ? info.targetSampleRate
                  : savedSampleRate,
          targetBitDepth:
              info.targetBitDepth != 0 ? info.targetBitDepth : savedBitDepth,
          isBitPerfectActive:
              info.isBitPerfectActive || (isBitPerfect && info.isUsbDac),
        ),
      ),
    );
  }

  Future<void> setDspPreference(String preference) async {
    safeEmit(state.copyWith(dspPreference: preference));
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.lookaheadLimiterEnabled, newEnabled);
    await prefs.setDouble(PrefsKeys.lookaheadLimiterThresholdDb, newThreshold);
    await prefs.setDouble(PrefsKeys.lookaheadLimiterReleaseMs, newRelease);
    await prefs.setDouble(
      'setting_lookahead_limiter_lookahead_ms',
      newLookahead,
    );
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
    } catch (e, st) {
      ErrorLogger.log('setSystemEffectsPolicy failed', error: e, stackTrace: st, category: 'SettingsCubit');
    }
  }

  Future<void> refreshSystemEffectsStatus() async {
    try {
      final result = await AudioEffectsChannel().detectSystemEffects();
      final status = result['status'] as String? ?? 'unknown';
      final bundles = (result['detectedBundles'] as List<dynamic>?)?.cast<String>() ?? [];
      if (!isClosed) {
        safeEmit(state.copyWith(
          systemEffectsStatus: status,
          systemEffectsBundles: bundles,
        ));
      }
    } catch (e, st) {
      ErrorLogger.log('refreshSystemEffectsStatus failed', error: e, stackTrace: st, category: 'SettingsCubit');
    }
  }

  Future<void> setBluetoothLatencyOffsetMs(int offsetMs) async {
    final clamped = offsetMs.clamp(0, 500);
    safeEmit(state.copyWith(bluetoothLatencyOffsetMs: clamped));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.bluetoothLatencyOffsetMs, clamped);
  }
}
