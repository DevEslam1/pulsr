// lib/core/network/network_change_monitor.dart
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../constants/channels.dart';

/// Emits an event whenever the active network path changes (Wi-Fi <-> mobile,
/// VPN up/down, Wi-Fi network switch, or any connectivity change).
///
/// googlevideo stream URLs are minted for the resolving egress IP. When the
/// user toggles a VPN mid-playback the cached URL keeps the *old* IP and the
/// edge answers 403. The player already retries once with a fresh resolve,
/// but the shared URL cache ([YtmUrlCache]) and the native DNS TTL cache still
/// serve the old-IP answer unless they are explicitly dropped on a path
/// change. This monitor is that trigger.
class NetworkChangeMonitor {
  NetworkChangeMonitor({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  /// connectivity_plus reports transport classes, so it cannot see Wi-Fi A ->
  /// Wi-Fi B. The native monitor hashes the active interface and addresses and
  /// pushes those changes here too.
  static const MethodChannel _nativeChannel =
      MethodChannel(PulsrChannels.proxy);

  StreamSubscription<List<ConnectivityResult>>? _sub;
  StreamController<void> _controller = StreamController<void>.broadcast();

  List<ConnectivityResult>? _lastResults;
  Timer? _debounce;
  bool _started = false;

  /// Fires on every debounced network-path change.
  Stream<void> get onNetworkChanged => _controller.stream;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    if (_controller.isClosed) {
      _controller = StreamController<void>.broadcast();
    }
    try {
      _lastResults = await _connectivity.checkConnectivity();
    } catch (_) {
      _lastResults = null;
    }
    if (!_started || _controller.isClosed) return;
    await _sub?.cancel();
    _nativeChannel.setMethodCallHandler(_onNativeCall);
    _sub = _connectivity.onConnectivityChanged.listen(_onResults);
  }

  Future<void> _onNativeCall(MethodCall call) async {
    if (call.method == 'onNetworkChanged' || call.method == 'onPathChanged') {
      _scheduleEmit('native:${call.method}');
    }
  }

  void _onResults(List<ConnectivityResult> results) {
    final prev = _lastResults;
    _lastResults = results;
    if (prev != null && _sameResults(prev, results)) return;
    _scheduleEmit('connectivity:$prev -> $results');
  }

  void _scheduleEmit(String detail) {
    // Collapse the flurry of events Android emits during a VPN handshake
    // into one invalidation + one re-resolve.
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), () {
      // Guard against the start()/dispose() race: start() subscribes after an
      // `await checkConnectivity()`, so dispose() can close the controller in
      // that window. A later event would then add onto a closed controller and
      // throw an uncaught StateError.
      if (_controller.isClosed) return;
      debugPrint('[NetworkChangeMonitor] Path changed: $detail');
      _controller.add(null);
    });
  }

  static bool _sameResults(
      List<ConnectivityResult> a, List<ConnectivityResult> b) {
    if (a.length != b.length) return false;
    final sa = {...a};
    return sa.containsAll(b);
  }

  Future<void> dispose() async {
    _started = false;
    _debounce?.cancel();
    _debounce = null;
    _nativeChannel.setMethodCallHandler(null);
    await _sub?.cancel();
    _sub = null;
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
