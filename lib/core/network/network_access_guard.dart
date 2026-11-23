// lib/core/network/network_access_guard.dart
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../constants/prefs_keys.dart';
import '../utils/error_logger.dart';

/// Fail-closed gate for outbound non-user-initiated or third-party HTTP calls.
abstract final class NetworkAccessGuard {
  /// Returns true when outbound requests are disallowed by build flavor
  /// (`AppConfig.isPure` / `!AppConfig.isCloudSyncAllowed`), active offline-only
  /// mode, or an unreadable preference store (fail closed).
  static Future<bool> isBlocked({
    SharedPreferences? prefs,
    String category = 'Network',
  }) async {
    if (!AppConfig.isCloudSyncAllowed) return true;
    try {
      final resolved = prefs ?? await SharedPreferences.getInstance();
      return resolved.getBool(PrefsKeys.offlineOnlyMode) == true;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to read offline-only preference; blocking outbound request',
        error: e,
        stackTrace: st,
        category: category,
      );
      return true;
    }
  }
}
