// lib/data/audio/player_prefs.dart
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/prefs_keys.dart';

/// Read-only snapshot of player-related preferences.
/// Provides typed getters with defaults to avoid scattered raw prefs calls.
class PlayerPrefs {
  final SharedPreferences? _prefs;

  const PlayerPrefs(this._prefs);

  bool get keepNotificationOnPause =>
      _prefs?.getBool(PrefsKeys.keepNotificationOnPause) ?? true;

  String? get languageCode =>
      _prefs?.getString(PrefsKeys.languageCode) ??
      _prefs?.getString(PrefsKeys.settingLanguage);

  bool get autoResumeOnReconnect =>
      _prefs?.getBool(PrefsKeys.autoResumeOnReconnect) ?? false;

  int get autoResumeTimeoutSec =>
      _prefs?.getInt(PrefsKeys.autoResumeTimeoutSec) ?? 90;

  bool get bitPerfectOutput =>
      _prefs?.getBool(PrefsKeys.bitPerfectOutput) ?? false;

  bool get bypassDspOnBitPerfect =>
      _prefs?.getBool(PrefsKeys.bypassDspOnBitPerfect) ?? true;

  String get replayGainMode =>
      _prefs?.getString(PrefsKeys.replayGainMode) ?? 'off';

  double get replayGainPreampWithRg =>
      _prefs?.getDouble(PrefsKeys.replayGainPreampWithRg) ?? 0.0;

  double get replayGainPreampWithoutRg =>
      _prefs?.getDouble(PrefsKeys.replayGainPreampWithoutRg) ?? 0.0;

  bool get hedgedResolutionEnabled =>
      _prefs?.getBool(PrefsKeys.hedgedResolutionEnabled) ?? true;

  bool get adaptiveQualityEnabled =>
      _prefs?.getBool(PrefsKeys.adaptiveQualityEnabled) ?? true;

  String get streamingQuality =>
      _prefs?.getString(PrefsKeys.streamingQuality) ?? 'high';

  String? get adaptiveRuntimeQuality =>
      _prefs?.getString(PrefsKeys.adaptiveRuntimeQuality);

  bool get offlineOnlyMode =>
      _prefs?.getBool(PrefsKeys.offlineOnlyMode) ?? false;

  bool get wifiOnlyMode => _prefs?.getBool(PrefsKeys.wifiOnlyMode) ?? false;

  bool get audioNormalizationEnabled =>
      _prefs?.getBool(PrefsKeys.audioNormalizationEnabled) ?? false;

  bool get playbackShuffle =>
      _prefs?.getBool(PrefsKeys.playbackShuffle) ?? false;

  String get playbackRepeatMode =>
      _prefs?.getString(PrefsKeys.playbackRepeatMode) ?? 'off';

  int get headsetClickWindowMs =>
      (_prefs?.getInt(PrefsKeys.headsetClickWindowMs) ?? 350).clamp(150, 800);

  bool get advancedPlaybackSpeed =>
      _prefs?.getBool(PrefsKeys.advancedPlaybackSpeed) ?? false;

  double get playbackSpeed => _prefs?.getDouble(PrefsKeys.playbackSpeed) ?? 1.0;

  double get playbackPitch => _prefs?.getDouble(PrefsKeys.playbackPitch) ?? 1.0;
}
