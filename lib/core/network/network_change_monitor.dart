// lib/core/network/network_change_monitor.dart
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Emits an event whenever the active network path changes (Wi-Fi <-> mobile,
/// VPN up/down, or any connectivity change).
///
/// googlevideo stream URLs are minted for the resolving egress IP. When the
/// user toggles a VPN mid-playback the cached URL keeps the *old* IP and the
/// edge answers 403. The player already retries once with a fresh resolve,
/// but the in-memory URL caches ([YtmUrlCache], `AudioHandler._streamCache`)
/// and the native DNS TTL cache still serve the old-IP answer unless they are
/// explicitly dropped on a path change. This monitor is that trigger.
class NetworkChangeMonitor {
  NetworkChangeMonitor({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  StreamSubscription<List<ConnectivityResult>>? _sub;
  final StreamController<void> _controller =
      StreamController<void>.broadcast();

  List<ConnectivityResult>? _lastResults;
  Timer? _debounce;
  bool _started = false;

  /// Fires on every debounced network-path change.
  Stream<void> get onNetworkChanged => _controller.stream;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      _lastResults = await _connectivity.checkConnectivity();
    } catch (_) {
      _lastResults = null;
    }
    _sub = _connectivity.onConnectivityChanged.listen(_onResults);
  }

  void _onResults(List<ConnectivityResult> results) {
    final prev = _lastResults;
    _lastResults = results;
    if (prev != null && _sameResults(prev, results)) return;
    // Collapse the flurry of events Android emits during a VPN handshake
    // into one invalidation + one re-resolve.
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), () {
      debugPrint('[NetworkChangeMonitor] Path changed: $prev -> $results');
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
    _debounce?.cancel();
    await _sub?.cancel();
    await _controller.close();
    _started = false;
  }
}
