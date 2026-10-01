// lib/features/player/cubit/dsp_telemetry_cubit.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/utils/error_logger.dart';
import '../../../data/audio/audio_effects_channel.dart';
import '../../../domain/models/dsp_telemetry.dart';

class DspTelemetryCubit extends Cubit<DspTelemetry> {
  final AudioEffectsChannel _channel;
  final Duration pollingInterval;
  final Duration retryInterval;
  Timer? _pollingTimer;
  Timer? _retryTimer;
  int _listenerCount = 0;
  int _consecutiveFailures = 0;
  bool _didLogFailure = false;
  bool _fetchInFlight = false;

  /// B3: after this many consecutive failed polls the timer is parked so a
  /// broken channel (non-Android, engine not ready, test fakes) cannot fire an
  /// unhandled async error on every 200ms tick.
  static const int _maxConsecutiveFailures = 3;

  DspTelemetryCubit({
    AudioEffectsChannel? channel,
    this.pollingInterval = const Duration(milliseconds: 200),
    this.retryInterval = const Duration(seconds: 3),
  })  : _channel = channel ?? AudioEffectsChannel(),
        super(const DspTelemetry.zero());

  @visibleForTesting
  bool get isRetryTimerActive => _retryTimer != null && _retryTimer!.isActive;

  @visibleForTesting
  bool get isPollingTimerActive =>
      _pollingTimer != null && _pollingTimer!.isActive;

  @visibleForTesting
  int get consecutiveFailures => _consecutiveFailures;

  @visibleForTesting
  int get listenerCount => _listenerCount;

  /// Increments consumer reference count and starts polling if first subscriber.
  void subscribe() {
    if (isClosed) return;
    _listenerCount++;
    if (_listenerCount == 1 && _pollingTimer == null) {
      _startPolling();
    }
  }

  /// Decrements consumer reference count and stops polling when zero.
  void unsubscribe() {
    if (_listenerCount <= 0) return;
    _listenerCount--;
    if (_listenerCount == 0) {
      _stopPolling();
    }
  }

  void _startPolling() {
    _stopTimer();
    _retryTimer?.cancel();
    _retryTimer = null;
    _consecutiveFailures = 0;
    _didLogFailure = false;
    _pollingTimer = Timer.periodic(pollingInterval, (_) {
      unawaited(_fetchTelemetry());
    });
    unawaited(_fetchTelemetry());
  }

  /// Cancels the timer only; keeps the current emitted value and listener count.
  void _stopTimer() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  void _stopPolling() {
    _stopTimer();
    _retryTimer?.cancel();
    _retryTimer = null;
    if (!isClosed) emit(const DspTelemetry.zero());
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    if (isClosed || _listenerCount == 0) return;
    _retryTimer = Timer(retryInterval, () {
      if (isClosed || _listenerCount == 0) return;
      unawaited(_fetchTelemetry());
    });
  }

  Future<void> refreshOnce() async {
    await _fetchTelemetry();
  }

  Future<void> _fetchTelemetry() async {
    // Skip this tick while a previous fetch is still in flight: the 200ms timer
    // can fire before the 250ms channel timeout, and overlapping polls could
    // emit telemetry out of order.
    if (_fetchInFlight) return;
    _fetchInFlight = true;
    try {
      final telemetry = await _channel.getTelemetry();
      if (isClosed) return;
      _consecutiveFailures = 0;
      _didLogFailure = false;
      _retryTimer?.cancel();
      _retryTimer = null;
      // A successful poll after the timer was parked resumes normal emission.
      if (_pollingTimer == null && _listenerCount > 0) {
        _startPolling();
        return;
      }
      emit(telemetry);
    } catch (e, st) {
      _consecutiveFailures++;
      if (!_didLogFailure) {
        _didLogFailure = true;
        ErrorLogger.log(
          'DSP telemetry poll failed (backing off after '
          '$_maxConsecutiveFailures failures)',
          error: e,
          stackTrace: st,
          category: 'DspTelemetry',
        );
      }
      if (_consecutiveFailures >= _maxConsecutiveFailures) {
        if (!isClosed) emit(const DspTelemetry.zero());
        _stopTimer();
        _scheduleRetry();
      }
    } finally {
      _fetchInFlight = false;
    }
  }

  @override
  Future<void> close() {
    _stopTimer();
    _retryTimer?.cancel();
    _retryTimer = null;
    return super.close();
  }
}
