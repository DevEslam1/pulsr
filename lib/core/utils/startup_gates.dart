// lib/core/utils/startup_gates.dart
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../constants/prefs_keys.dart';

/// Pure cold-start feature gates derived from persisted settings.
///
/// These helpers exist so the ordering contract is explicit and testable:
/// callers MUST read [SharedPreferences] (awaiting it) before deciding which
/// online initializers may run, otherwise the offline-only setting is observed
/// on a later microtask and ignored.
class StartupGates {
  const StartupGates._();

  static bool isOfflineOnly(SharedPreferences? prefs) =>
      prefs?.getBool(PrefsKeys.offlineOnlyMode) ?? false;

  /// YouTube Music initializers may run only in YTM-enabled, online builds.
  static bool onlineAllowed(SharedPreferences? prefs) =>
      AppConfig.ytmEnabled && !isOfflineOnly(prefs);

  /// Cloud sync / account / scrobbler initializers respect offline-only mode.
  static bool cloudSyncAllowed(SharedPreferences? prefs) =>
      AppConfig.isCloudSyncAllowed && !isOfflineOnly(prefs);
}
