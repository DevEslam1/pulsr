// lib/data/audio/connectivity_monitor.dart
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../core/utils/error_logger.dart';

enum NetworkStatus { online, offline }

/// Monitors network connectivity for online streaming and recovery.
///
/// Note: "online" means a network interface is up, not that the internet is
/// reachable (captive portals / dead Wi-Fi still report online).
class ConnectivityMonitor {
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _isOnline = true;
  bool _receivedStreamEvent = false;
  bool _disposed = false;
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
    _sub = _connectivity.onConnectivityChanged.listen(
      (results) {
        _receivedStreamEvent = true;
        _apply(results);
      },
      onError: (Object e, StackTrace st) {
        ErrorLogger.log('Connectivity stream error',
            error: e, stackTrace: st, category: 'ConnectivityMonitor');
      },
    );
    // The stream only emits on CHANGE, so an app started offline would
    // otherwise believe it is online until the next change.
    unawaited(_checkInitial());
  }

  Future<void> _checkInitial() async {
    try {
      final results = await _connectivity.checkConnectivity();
      // A real stream event that arrived meanwhile is newer than this read.
      if (!_receivedStreamEvent) _apply(results);
    } catch (e, st) {
      ErrorLogger.log('Initial connectivity check failed',
          error: e, stackTrace: st, category: 'ConnectivityMonitor');
    }
  }

  void _apply(List<ConnectivityResult> results) {
    if (_disposed) return;
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online == _isOnline) return;
    _isOnline = online;
    if (!_statusController.isClosed) {
      _statusController
          .add(online ? NetworkStatus.online : NetworkStatus.offline);
    }
    // A throwing callback must not break the subscription's delivery.
    try {
      if (online) {
        onNetworkRestored?.call();
      } else {
        onNetworkLost?.call();
      }
    } catch (e, st) {
      ErrorLogger.log('Connectivity callback error',
          error: e, stackTrace: st, category: 'ConnectivityMonitor');
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _sub?.cancel();
    _sub = null;
    _statusController.close();
  }
}
