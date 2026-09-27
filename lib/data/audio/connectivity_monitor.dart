// lib/data/audio/connectivity_monitor.dart
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

enum NetworkStatus { online, offline }

/// Monitors network connectivity for online streaming and recovery.
class ConnectivityMonitor {
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _isOnline = true;
  bool get isOnline => _isOnline;

  final StreamController<NetworkStatus> _statusController =
      StreamController<NetworkStatus>.broadcast();
  Stream<NetworkStatus> get statusStream => _statusController.stream;

  final void Function()? onNetworkLost;
  final void Function()? onNetworkRestored;

  ConnectivityMonitor({
    Connectivity? connectivity,
    this.onNetworkLost,
    this.onNetworkRestored,
  }) : _connectivity = connectivity ?? Connectivity() {
    _init();
  }

  void _init() {
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online != _isOnline) {
        _isOnline = online;
        final status = online ? NetworkStatus.online : NetworkStatus.offline;
        _statusController.add(status);
        if (online) {
          onNetworkRestored?.call();
        } else {
          onNetworkLost?.call();
        }
      }
    });
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _statusController.close();
  }
}
