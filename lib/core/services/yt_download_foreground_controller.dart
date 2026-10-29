// lib/core/services/yt_download_foreground_controller.dart
import 'package:flutter/services.dart';

import '../constants/channels.dart';

enum _ForegroundPhase { idle, starting, running, stopping }

/// Owns the download foreground service lifecycle and its progress channel.
///
/// The queue/service state lives in [YtDownloadService]; this collaborator
/// only answers "start, update, or stop the notification" and defers a stop
/// that races an in-flight start.
class YtDownloadForegroundController {
  YtDownloadForegroundController({
    MethodChannel? channel,
    this.onDeferredIdle,
  }) : _channel = channel ?? const MethodChannel(PulsrChannels.ytDownload);

  final MethodChannel _channel;

  /// Re-checks the owner's queue before honouring a stop that was deferred
  /// behind an in-flight start; new work may have arrived in that window.
  final void Function()? onDeferredIdle;

  _ForegroundPhase _phase = _ForegroundPhase.idle;
  int _startsInFlight = 0;
  bool _stopRequested = false;

  static const int _publishMinIntervalMs = 250;
  final Map<String, int> _lastPublishMs = {};

  /// Brings the native download notification up for a queued job.
  void start(String videoId, String title) {
    _lastPublishMs.remove(videoId);
    _startsInFlight++;
    if (_phase != _ForegroundPhase.running) {
      _phase = _ForegroundPhase.starting;
    }
    _channel.invokeMethod('startDownloadForeground', {
      'videoId': videoId,
      'title': title,
    }).then((ok) {
      // F13: only claim foreground protection once the platform confirms it.
      _startsInFlight--;
      if (ok == true) {
        _phase = _ForegroundPhase.running;
      } else if (_startsInFlight == 0 && _phase == _ForegroundPhase.starting) {
        _phase = _ForegroundPhase.idle;
      }
      _drainDeferredStop();
    }).catchError((_) {
      _startsInFlight--;
      if (_startsInFlight == 0 && _phase == _ForegroundPhase.starting) {
        _phase = _ForegroundPhase.idle;
      }
      _drainDeferredStop();
      return null;
    });
  }

  void _drainDeferredStop() {
    if (!_stopRequested || _startsInFlight > 0) return;
    _stopRequested = false;
    final recheck = onDeferredIdle;
    if (recheck != null) {
      recheck();
    } else {
      stopIfIdle();
    }
  }

  /// Coalesced progress publish. A terminal value is always published so the
  /// notification cannot be left stale.
  void publish(String videoId, String title, double? fraction) {
    if (_phase != _ForegroundPhase.running || fraction == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastPublishMs[videoId] ?? 0;
    final isTerminal = fraction >= 1.0;
    if (!isTerminal && now - last < _publishMinIntervalMs) return;
    _lastPublishMs[videoId] = now;
    _channel.invokeMethod('updateDownloadProgress', {
      'videoId': videoId,
      'title': title,
      'progress': (fraction * 100).round().clamp(0, 100),
    }).catchError((_) => null);
  }

  /// Removes a job from the native notification without pretending the file
  /// finished. A failed transfer used to stay in the service's map at its last
  /// percentage for as long as another download kept the service alive.
  void release(String videoId) {
    _lastPublishMs.remove(videoId);
    if (_phase != _ForegroundPhase.running &&
        _phase != _ForegroundPhase.starting) {
      return;
    }
    _channel.invokeMethod('updateDownloadProgress', {
      'videoId': videoId,
      'title': '',
      'progress': 100,
    }).catchError((_) => null);
  }

  /// Stops the service when the caller has established that nothing is left to
  /// download. A start in flight is stopped once the platform answers.
  void stopIfIdle() {
    switch (_phase) {
      case _ForegroundPhase.idle:
        return;
      case _ForegroundPhase.starting:
        _stopRequested = true;
        return;
      case _ForegroundPhase.stopping:
        return;
      case _ForegroundPhase.running:
        break;
    }

    _phase = _ForegroundPhase.stopping;
    _channel.invokeMethod('stopDownloadForeground').then((_) {
      if (_phase == _ForegroundPhase.stopping) {
        _phase = _ForegroundPhase.idle;
      }
    }).catchError((_) {
      if (_phase == _ForegroundPhase.stopping) {
        _phase = _ForegroundPhase.idle;
      }
      return null;
    });
  }
}
