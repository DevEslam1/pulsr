// lib/core/network/connectivity_guard.dart
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../constants/channels.dart';
import '../utils/error_logger.dart';

/// Provides a lightweight connectivity pre-check for online fetch operations (I10).
class ConnectivityGuard {
  static Connectivity _connectivity = Connectivity();
  static const MethodChannel _nativeChannel =
      MethodChannel(PulsrChannels.proxy);

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
  ///
  /// connectivity_plus reports an active VPN as `vpn` and hides its underlying
  /// transport, so VPN-over-cellular used to look unmetered and allowed
  /// aggressive preloading. Prefer the platform's active-network metered flag.
  static Future<bool> isMeteredConnection() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final state = await _nativeChannel
            .invokeMapMethod<String, dynamic>('getNetworkState');
        final metered = state?['metered'];
        if (metered is bool) return metered;
      } on MissingPluginException {
        // Fall through to the plugin transport heuristic.
      } on PlatformException {
        // Fall through to the plugin transport heuristic.
      } catch (e, st) {
        ErrorLogger.log('Native metered-connection query failed',
            error: e, stackTrace: st, category: 'Network');
      }
    }
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
