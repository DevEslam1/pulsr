// lib/features/settings/cubit/settings_cubit.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/network/app_http_overrides.dart';
import '../../../core/network/proxy_config.dart';
import '../../../core/utils/error_logger.dart';
import '../../../data/scanner/media_scanner_service.dart';
import '../../player/presentation/widgets/audio_visualizer.dart';
import 'settings_state.dart';

@singleton
class SettingsCubit extends Cubit<SettingsState> {
  final MediaScannerService _scannerService;
  static const MethodChannel _proxyChannel = MethodChannel('com.pulsr.music/proxy');

  static const String _keyGapless = 'setting_gapless';
  static const String _keyCrossfade = 'setting_crossfade';
  static const String _keyMinDuration = 'setting_min_duration';
  static const String _keyAutoHideSystemMedia = 'setting_auto_hide_system_media';
  static const String _keyDynamicTheme = 'setting_dynamic_theme';
  static const String _keyThemeColorSource = 'setting_theme_color_source';
  static const String _keyResumeAfterInterruption = 'setting_resume_after_interruption';
  static const String _keyWaveformSeekBar = 'setting_waveform_seek_bar';
  static const String _keyThemeMode = 'setting_theme_mode';
  static const String _keyCustomAccent = 'setting_custom_accent';
  static const String _keyPlayerThemeMode = 'setting_player_theme_mode';
  static const String _keyVisualizerStyle = 'setting_visualizer_style';
  static const String _keyMiniPlayerSwipeLeft = 'setting_mini_player_swipe_left';
  static const String _keyMiniPlayerSwipeRight = 'setting_mini_player_swipe_right';
  static const String _keyNowPlayingDoubleTap = 'setting_now_playing_double_tap';
  static const String _keyNowPlayingArtworkSwipe = 'setting_now_playing_artwork_swipe';
  static const String _keyReplayGainMode = 'setting_replay_gain_mode';
  static const String _keyReplayGainPreampWithRg = 'setting_replay_gain_preamp_with_rg';
  static const String _keyReplayGainPreampWithoutRg = 'setting_replay_gain_preamp_without_rg';
  static const String _keyStreamingQuality = 'setting_streaming_quality';
  static const String _keyDownloadQuality = 'setting_download_quality';
  static const String _keyWifiOnlyMode = 'setting_wifi_only_mode';
  static const String _keyOfflineOnlyMode = 'setting_offline_only_mode';

  // Proxy Keys
  static const String _keyProxyEnabled = 'setting_proxy_enabled';
  static const String _keyProxyType = 'setting_proxy_type';
  static const String _keyProxyHost = 'setting_proxy_host';
  static const String _keyProxyPort = 'setting_proxy_port';
  static const String _keyProxyUsername = 'setting_proxy_username';
  static const String _keyProxyPassword = 'setting_proxy_password';
  static const String _keyProxyBypassHosts = 'setting_proxy_bypass_hosts';

  SettingsCubit({required MediaScannerService scannerService})
      : _scannerService = scannerService,
        super(const SettingsState()) {
    _loadPreferences();
  }

  void clearError() {
    emit(state.copyWith(errorMessage: null));
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

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeModeStr = prefs.getString(_keyThemeMode) ?? AppThemeMode.dark.name;
      final themeMode = AppThemeMode.values.firstWhere(
        (e) => e.name == themeModeStr,
        orElse: () => AppThemeMode.dark,
      );
      final customAccentValue = prefs.getInt(_keyCustomAccent) ?? 0xFF9B9EF5;

      final playerThemeStr = prefs.getString(_keyPlayerThemeMode) ?? PlayerThemeMode.classic.name;
      final playerThemeMode = PlayerThemeMode.values.firstWhere(
        (e) => e.name == playerThemeStr,
        orElse: () => PlayerThemeMode.classic,
      );

      final visualizerStyleStr = prefs.getString(_keyVisualizerStyle) ?? VisualizerStyle.bar.name;
      final visualizerStyle = VisualizerStyle.values.firstWhere(
        (e) => e.name == visualizerStyleStr,
        orElse: () => VisualizerStyle.bar,
      );

      final miniPlayerSwipeLeftStr = prefs.getString(_keyMiniPlayerSwipeLeft) ?? MiniPlayerSwipeAction.next.name;
      final miniPlayerSwipeLeft = MiniPlayerSwipeAction.values.firstWhere(
        (e) => e.name == miniPlayerSwipeLeftStr,
        orElse: () => MiniPlayerSwipeAction.next,
      );

      final miniPlayerSwipeRightStr = prefs.getString(_keyMiniPlayerSwipeRight) ?? MiniPlayerSwipeAction.prev.name;
      final miniPlayerSwipeRight = MiniPlayerSwipeAction.values.firstWhere(
        (e) => e.name == miniPlayerSwipeRightStr,
        orElse: () => MiniPlayerSwipeAction.prev,
      );

      final nowPlayingDoubleTapStr = prefs.getString(_keyNowPlayingDoubleTap) ?? NowPlayingDoubleTapAction.toggleFavorite.name;
      final nowPlayingDoubleTap = NowPlayingDoubleTapAction.values.firstWhere(
        (e) => e.name == nowPlayingDoubleTapStr,
        orElse: () => NowPlayingDoubleTapAction.toggleFavorite,
      );

      final nowPlayingArtworkSwipeStr = prefs.getString(_keyNowPlayingArtworkSwipe) ?? NowPlayingArtworkSwipeAction.nextPrev.name;
      final nowPlayingArtworkSwipe = NowPlayingArtworkSwipeAction.values.firstWhere(
        (e) => e.name == nowPlayingArtworkSwipeStr,
        orElse: () => NowPlayingArtworkSwipeAction.nextPrev,
      );

      final replayGainModeStr = prefs.getString(_keyReplayGainMode) ?? ReplayGainMode.track.name;
      final replayGainMode = ReplayGainMode.values.firstWhere(
        (e) => e.name == replayGainModeStr,
        orElse: () => ReplayGainMode.track,
      );
      final replayGainPreampWithRg = prefs.getDouble(_keyReplayGainPreampWithRg) ?? 0.0;
      final replayGainPreampWithoutRg = prefs.getDouble(_keyReplayGainPreampWithoutRg) ?? -3.0;

      final streamingQualityStr = prefs.getString(_keyStreamingQuality) ?? YtmAudioQuality.high.name;
      final streamingQuality = YtmAudioQuality.values.firstWhere(
        (e) => e.name == streamingQualityStr,
        orElse: () => YtmAudioQuality.high,
      );

      final downloadQualityStr = prefs.getString(_keyDownloadQuality) ?? YtmAudioQuality.high.name;
      final downloadQuality = YtmAudioQuality.values.firstWhere(
        (e) => e.name == downloadQualityStr,
        orElse: () => YtmAudioQuality.high,
      );

      final wifiOnlyMode = prefs.getBool(_keyWifiOnlyMode) ?? false;
      final offlineOnlyMode = prefs.getBool(_keyOfflineOnlyMode) ?? false;

      // Proxy Settings
      final proxyEnabled = prefs.getBool(_keyProxyEnabled) ?? false;
      final proxyTypeStr = prefs.getString(_keyProxyType) ?? AppProxyType.http.name;
      final proxyType = AppProxyType.values.firstWhere(
        (e) => e.name == proxyTypeStr,
        orElse: () => AppProxyType.http,
      );
      final proxyHost = prefs.getString(_keyProxyHost) ?? '';
      final proxyPort = prefs.getInt(_keyProxyPort) ?? 8080;
      final proxyUsername = prefs.getString(_keyProxyUsername) ?? '';
      final proxyPassword = prefs.getString(_keyProxyPassword) ?? '';
      final proxyBypassHosts = prefs.getString(_keyProxyBypassHosts) ?? 'localhost, 127.0.0.1';

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

      final newState = state.copyWith(
        gaplessPlayback: prefs.getBool(_keyGapless) ?? true,
        crossfadeSeconds: prefs.getDouble(_keyCrossfade) ?? 0.0,
        minDurationSec: prefs.getInt(_keyMinDuration) ?? 30,
        autoHideSystemMedia: prefs.getBool(_keyAutoHideSystemMedia) ?? true,
        themeColorSource: themeColorSource,
        resumeAfterInterruption: prefs.getBool(_keyResumeAfterInterruption) ?? true,
        waveformSeekBarEnabled: prefs.getBool(_keyWaveformSeekBar) ?? true,
        themeMode: themeMode,
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
        wifiOnlyMode: wifiOnlyMode,
        offlineOnlyMode: offlineOnlyMode,
        proxyEnabled: proxyEnabled,
        proxyType: proxyType,
        proxyHost: proxyHost,
        proxyPort: proxyPort,
        proxyUsername: proxyUsername,
        proxyPassword: proxyPassword,
        proxyBypassHosts: proxyBypassHosts,
      );

      emit(newState);
      await _syncProxySettings(newState.proxyConfig);
    } catch (e, st) {
      ErrorLogger.log('Failed to load settings preferences from SharedPreferences', error: e, stackTrace: st, category: 'SettingsCubit');
    }
  }

  Future<void> setGapless(bool value) async {
    emit(state.copyWith(gaplessPlayback: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGapless, value);
  }

  Future<void> setCrossfade(double seconds) async {
    emit(state.copyWith(crossfadeSeconds: seconds));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyCrossfade, seconds);
  }

  Future<void> setMinDuration(int seconds) async {
    emit(state.copyWith(minDurationSec: seconds));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMinDuration, seconds);
  }

  Future<void> setAutoHideSystemMedia(bool value) async {
    emit(state.copyWith(autoHideSystemMedia: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoHideSystemMedia, value);
  }

  Future<void> setThemeColorSource(ThemeColorSource source) async {
    emit(state.copyWith(themeColorSource: source));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeColorSource, source.name);
    await prefs.setBool(_keyDynamicTheme, source == ThemeColorSource.artwork);
  }

  Future<void> setDynamicTheming(bool value) =>
      setThemeColorSource(value ? ThemeColorSource.artwork : ThemeColorSource.custom);

  Future<void> setResumeAfterInterruption(bool value) async {
    emit(state.copyWith(resumeAfterInterruption: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyResumeAfterInterruption, value);
  }

  Future<void> setWaveformSeekBar(bool value) async {
    emit(state.copyWith(waveformSeekBarEnabled: value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyWaveformSeekBar, value);
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    emit(state.copyWith(themeMode: mode));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, mode.name);
  }

  Future<void> setCustomAccentColor(Color color) async {
    final colorVal = color.toARGB32();
    emit(state.copyWith(customAccentColorValue: colorVal));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCustomAccent, colorVal);
  }

  Future<void> setPlayerThemeMode(PlayerThemeMode mode) async {
    emit(state.copyWith(playerThemeMode: mode));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPlayerThemeMode, mode.name);
  }

  Future<void> setVisualizerStyle(VisualizerStyle style) async {
    emit(state.copyWith(visualizerStyle: style));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyVisualizerStyle, style.name);
  }

  Future<void> setMiniPlayerSwipeLeft(MiniPlayerSwipeAction action) async {
    emit(state.copyWith(miniPlayerSwipeLeft: action));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMiniPlayerSwipeLeft, action.name);
  }

  Future<void> setMiniPlayerSwipeRight(MiniPlayerSwipeAction action) async {
    emit(state.copyWith(miniPlayerSwipeRight: action));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMiniPlayerSwipeRight, action.name);
  }

  Future<void> setNowPlayingDoubleTap(NowPlayingDoubleTapAction action) async {
    emit(state.copyWith(nowPlayingDoubleTap: action));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNowPlayingDoubleTap, action.name);
  }

  Future<void> setNowPlayingArtworkSwipe(NowPlayingArtworkSwipeAction action) async {
    emit(state.copyWith(nowPlayingArtworkSwipe: action));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNowPlayingArtworkSwipe, action.name);
  }

  Future<void> setReplayGainMode(ReplayGainMode mode) async {
    emit(state.copyWith(replayGainMode: mode));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyReplayGainMode, mode.name);
  }

  Future<void> setReplayGainPreampWithRg(double db) async {
    emit(state.copyWith(replayGainPreampWithRg: db));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyReplayGainPreampWithRg, db);
  }

  Future<void> setReplayGainPreampWithoutRg(double db) async {
    emit(state.copyWith(replayGainPreampWithoutRg: db));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyReplayGainPreampWithoutRg, db);
  }

  Future<void> setStreamingQuality(YtmAudioQuality quality) async {
    emit(state.copyWith(streamingQuality: quality));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyStreamingQuality, quality.name);
  }

  Future<void> setDownloadQuality(YtmAudioQuality quality) async {
    emit(state.copyWith(downloadQuality: quality));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDownloadQuality, quality.name);
  }

  Future<void> setWifiOnlyMode(bool enabled) async {
    emit(state.copyWith(wifiOnlyMode: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyWifiOnlyMode, enabled);
  }

  Future<void> setOfflineOnlyMode(bool enabled) async {
    emit(state.copyWith(offlineOnlyMode: enabled));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOfflineOnlyMode, enabled);
  }

  // --- Proxy Settings Actions ---

  Future<void> setProxyEnabled(bool enabled) async {
    final updated = state.copyWith(proxyEnabled: enabled);
    emit(updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyProxyEnabled, enabled);
    await _syncProxySettings(updated.proxyConfig);
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
    final newConfig = ProxyConfig(
      enabled: enabled,
      type: type,
      host: host.trim(),
      port: port,
      username: username?.trim() ?? '',
      password: password ?? '',
      bypassHosts: bypassHosts ?? 'localhost, 127.0.0.1',
    );

    final updated = state.copyWith(
      proxyEnabled: newConfig.enabled,
      proxyType: newConfig.type,
      proxyHost: newConfig.host,
      proxyPort: newConfig.port,
      proxyUsername: newConfig.username,
      proxyPassword: newConfig.password,
      proxyBypassHosts: newConfig.bypassHosts,
    );

    emit(updated);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyProxyEnabled, newConfig.enabled);
    await prefs.setString(_keyProxyType, newConfig.type.name);
    await prefs.setString(_keyProxyHost, newConfig.host);
    await prefs.setInt(_keyProxyPort, newConfig.port);
    await prefs.setString(_keyProxyUsername, newConfig.username);
    await prefs.setString(_keyProxyPassword, newConfig.password);
    await prefs.setString(_keyProxyBypassHosts, newConfig.bypassHosts);

    await _syncProxySettings(newConfig);
  }

  /// Tests connectivity through the provided or current proxy config.
  Future<({bool success, int latencyMs, String? error})> testProxyConnection([
    ProxyConfig? config,
  ]) async {
    final configToTest = config ?? state.proxyConfig;
    return AppHttpOverrides.instance.testConnection(
      configToTest: configToTest,
    );
  }

  Future<int> rescanLibrary() async {
    emit(state.copyWith(isScanning: true, scanResultCount: null, errorMessage: null));
    try {
      final count = await _scannerService.scanDeviceLibrary(
        ignoreShortFiles: state.minDurationSec > 0,
        minDurationSec: state.minDurationSec,
        autoHideSystemMedia: state.autoHideSystemMedia,
      );
      emit(state.copyWith(isScanning: false, scanResultCount: count));
      return count;
    } catch (e) {
      emit(state.copyWith(isScanning: false, errorMessage: e.toString()));
      return 0;
    }
  }
}
