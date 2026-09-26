// lib/core/network/connectivity_guard.dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

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
    } catch (_) {
      return true;
    }
  }
}
