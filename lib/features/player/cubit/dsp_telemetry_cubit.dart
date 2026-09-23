// lib/features/player/cubit/dsp_telemetry_cubit.dart
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/audio/audio_effects_channel.dart';
import '../../../domain/models/dsp_telemetry.dart';

class DspTelemetryCubit extends Cubit<DspTelemetry> {
  final AudioEffectsChannel _channel;
  Timer? _pollingTimer;
  int _listenerCount = 0;

  DspTelemetryCubit({AudioEffectsChannel? channel})
      : _channel = channel ?? AudioEffectsChannel(),
        super(const DspTelemetry.zero());

  /// Increments consumer reference count and starts polling if first subscriber.
  void subscribe() {
    _listenerCount++;
    if (_listenerCount == 1 && _pollingTimer == null) {
      _startPolling();
    }
  }

  /// Decrements consumer reference count and stops polling when zero.
  void unsubscribe() {
    _listenerCount = (_listenerCount - 1).clamp(0, 9999);
    if (_listenerCount == 0) {
      _stopPolling();
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      _fetchTelemetry();
    });
    _fetchTelemetry();
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    emit(const DspTelemetry.zero());
  }

  Future<void> refreshOnce() async {
    await _fetchTelemetry();
  }

  Future<void> _fetchTelemetry() async {
    final telemetry = await _channel.getTelemetry();
    if (!isClosed) {
      emit(telemetry);
    }
  }

  @override
  Future<void> close() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    return super.close();
  }
}
