// lib/data/audio/native_dsd_session.dart
//
// Dedicated Native DSD Playback Session (Section 8.2 & Section 5.1).
// Replaces fake WAV playback through ExoPlayer with a direct pull/pump
// session driving the UAC2 USB sink in DSD_U32 native mode.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/models/audio_quality_info.dart';
import '../services/usb_exclusive_service.dart';
import 'dsd_decoder_helper.dart';
import 'native_dsd_producer.dart';
import 'playback_backend.dart';

/// Thrown when a DSD track cannot be played natively and must fall back.
class DsdFallbackRequiredException implements Exception {
  final String message;
  const DsdFallbackRequiredException(this.message);

  @override
  String toString() => 'DsdFallbackRequiredException: $message';
}

/// Dedicated native DSD playback backend driving the USB DAC via usbfs.
class NativeDsdSession implements PlaybackBackend {
  final UsbExclusiveService usbService;
  final NativeDsdProducer producer;

  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();
  final StreamController<void> _completedController =
      StreamController<void>.broadcast();

  MediaItem? _currentItem;
  MediaItem? get currentItem => _currentItem;
  Timer? _positionTimer;
  bool _hardwareVolumeEnabled = false;
  bool _disposed = false;

  NativeDsdSession({
    UsbExclusiveService? usb,
    NativeDsdProducer? producer,
  })  : usbService = usb ?? UsbExclusiveService(),
        producer = producer ?? NativeDsdProducer();

  void setHardwareVolumeEnabled(bool enabled) {
    _hardwareVolumeEnabled = enabled;
  }

  @override
  BackendCapabilities get capabilities => BackendCapabilities.localDsd;

  @override
  Future<void> prepare(MediaItem item, {MediaItem? next}) async {
    _currentItem = item;
    final path = item.extras?['path'] as String? ?? item.id;
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('DSD file not found', path);
    }

    final bytes = await file.readAsBytes();
    final ext = path.split('.').last.toLowerCase();

    final Uint8List dsdL;
    final Uint8List dsdR;
    final int dsdRate;
    final int bitOrder;

    if (ext == 'dsf') {
      final parsed = DsdDecoderHelper.parseDsfBytes(bytes);
      dsdL = parsed.dsdL;
      dsdR = parsed.dsdR;
      dsdRate = parsed.dsdRate;
      bitOrder = parsed.msbFirst ? 1 : 0;
    } else if (ext == 'dff') {
      final parsed = DsdDecoderHelper.parseDffBytes(bytes);
      dsdL = parsed.dsdL;
      dsdR = parsed.dsdR;
      dsdRate = parsed.dsdRate;
      bitOrder = 1; // MSB first (DFF)
    } else {
      throw DsdFallbackRequiredException('Unsupported DSD format extension: .$ext');
    }

    // Probe DAC for exact native DSD alt setting tuple (§8.2: no first-tuple fallback)
    final caps = await DsdDecoderHelper.probeDopCapabilities();
    final tuple = caps.findTupleForRate(dsdRate);
    if (tuple == null) {
      throw DsdFallbackRequiredException(
        'No exact UAC2 native DSD alternate setting tuple found for DSD$dsdRate',
      );
    }

    // Open native DSD stream on the DAC
    final opened = await producer.openStream(tuple, strict: true);
    if (!opened) {
      throw DsdFallbackRequiredException(
        'Failed to claim UAC2 interface and activate native DSD alt setting',
      );
    }

    // Prepare producer blocks
    producer.prepare(
      left: dsdL,
      right: dsdR,
      dsdRate: dsdRate,
      msbFirst: bitOrder == 1,
    );

    AudioQualityInfo.dsdNativeActive = true;
    AudioQualityInfo.dsdDopActive = false;

    _durationController.add(producer.totalDuration);
    _emitState(AudioProcessingState.ready, playing: false);
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    if (producer.state == NativeDsdProducerState.completed) {
      producer.seek(Duration.zero);
    }
    _startPositionTimer();
    _emitState(AudioProcessingState.ready, playing: true);
    unawaited(_pumpAndWatch());
  }

  Future<void> _pumpAndWatch() async {
    try {
      await producer.startPumping();
      if (producer.state == NativeDsdProducerState.completed) {
        _stopPositionTimer();
        _positionController.add(producer.totalDuration);
        _emitState(AudioProcessingState.completed, playing: false);
        if (!_completedController.isClosed) {
          _completedController.add(null);
        }
      } else if (producer.state == NativeDsdProducerState.stopped &&
          producer.xrunCount >= NativeDsdProducer.kMaxXrunsBeforeFallback) {
        // Starvation/xrun fallback triggered
        AudioQualityInfo.dsdNativeActive = false;
        _stopPositionTimer();
        _emitState(AudioProcessingState.error, playing: false);
      }
    } catch (e, st) {
      ErrorLogger.log('NativeDsdSession pumping error',
          error: e, stackTrace: st, category: 'NativeDsdSession');
      AudioQualityInfo.dsdNativeActive = false;
      _stopPositionTimer();
      _emitState(AudioProcessingState.error, playing: false);
    }
  }

  @override
  Future<void> pause() async {
    if (_disposed) return;
    _stopPositionTimer();
    producer.pause();
    _emitState(AudioProcessingState.ready, playing: false);
  }

  @override
  Future<void> seek(Duration position) async {
    if (_disposed) return;
    producer.seek(position);
    _positionController.add(producer.currentPosition);
    _emitState(
      AudioProcessingState.ready,
      playing: producer.isRunning && !producer.isPaused,
    );
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    _stopPositionTimer();
    await producer.stop();
    AudioQualityInfo.dsdNativeActive = false;
    _emitState(AudioProcessingState.idle, playing: false);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _stopPositionTimer();
    await producer.stop();
    AudioQualityInfo.dsdNativeActive = false;
    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
    await _completedController.close();
  }

  @override
  Future<void> setVolume(double volume) async {
    // DSD Volume Policy (§8.2 & §14 D3):
    // 1-bit DSD bitstreams cannot be mathematically scaled in software
    // without converting to PCM. If hardware volume is supported & enabled,
    // apply it to the DAC's Feature Unit; otherwise volume remains at unity.
    if (_hardwareVolumeEnabled) {
      try {
        await usbService.setHardwareVolume(volume);
      } catch (_) {}
    }
  }

  void _startPositionTimer() {
    _stopPositionTimer();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_disposed && !_positionController.isClosed) {
        _positionController.add(producer.currentPosition);
      }
    });
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  void _emitState(AudioProcessingState processingState, {required bool playing}) {
    if (_stateController.isClosed) return;
    _stateController.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: processingState,
        playing: playing,
        updatePosition: producer.currentPosition,
        bufferedPosition: producer.currentPosition,
        speed: 1.0,
      ),
    );
  }

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<PlaybackState> get stateStream => _stateController.stream;

  @override
  Stream<void> get completedStream => _completedController.stream;
}
