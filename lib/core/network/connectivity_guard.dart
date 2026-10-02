// lib/core/network/connectivity_guard.dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../utils/error_logger.dart';

/// Provides a lightweight connectivity pre-check for online fetch operations (I10).
class ConnectivityGuard {
  static Connectivity _connectivity = Connectivity();

  @visibleForTesting
  static void setMockConnectivity(Connectivity connectivity) {
    _connectivity = connectivity;
  }

  /// Returns true if any active network interface is connected (Wi-Fi, mobile, ethernet, VPN).
  /// Falls back to true if the check encounters an unexpected error so offline false-positives
  /// do not block requests when platforms lack connectivity implementations.
  static Future<bool> hasConnection() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (e, st) {
      // Fail open, but record why: a platform without a connectivity
      // implementation or a transient plugin failure is the only reason this
      // path runs, and silently swallowing it hid those cases entirely.
      ErrorLogger.log('Connectivity pre-check failed; failing open',
          error: e, stackTrace: st, category: 'Network');
      return true;
    }
  }

  /// Returns true if the device is exclusively on a metered cellular connection.
  static Future<bool> isMeteredConnection() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.contains(ConnectivityResult.mobile) &&
          !results.contains(ConnectivityResult.wifi) &&
          !results.contains(ConnectivityResult.ethernet);
    } catch (e, st) {
      ErrorLogger.log('Metered-connection check failed; assuming unmetered',
          error: e, stackTrace: st, category: 'Network');
      return false;
    }
  }
}
