// lib/data/audio/network_quality_indicator.dart
import 'dart:async';

/// Samples download speed every 5s and provides 1-4 signal strength bars.
class NetworkQualityIndicator {
  int _currentBars = 4; // 1 to 4
  int get currentBars => _currentBars;

  double _lastSpeedKbps = 1000.0;
  double get lastSpeedKbps => _lastSpeedKbps;

  final StreamController<int> _barsController =
      StreamController<int>.broadcast();
  Stream<int> get barsStream => _barsController.stream;

  Timer? _timer;

  NetworkQualityIndicator() {
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      _evaluateQuality();
    });
  }

  void reportBytesDownloaded(int bytes, Duration elapsed) {
    if (elapsed.inMilliseconds <= 0) return;
    final kbps = (bytes * 8) / elapsed.inMilliseconds;
    _lastSpeedKbps = kbps;
    _evaluateQuality();
  }

  void _evaluateQuality() {
    int bars;
    if (_lastSpeedKbps < 128) {
      bars = 1;
    } else if (_lastSpeedKbps < 500) {
      bars = 2;
    } else if (_lastSpeedKbps < 1500) {
      bars = 3;
    } else {
      bars = 4;
    }
    if (bars != _currentBars) {
      _currentBars = bars;
      _barsController.add(bars);
    }
  }

  void dispose() {
    _timer?.cancel();
    _barsController.close();
  }
}
