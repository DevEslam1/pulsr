// lib/data/audio/native_dsd_session.dart
//
// Dedicated Native DSD playback session (Section 8.2).
//
// ExoPlayer cannot render DSD: a "silent WAV" source would only fake a
// timeline while the real stream is somewhere else. This session is the
// backend instead. It owns the UAC2 alternate setting, pumps DSD blocks with
// backpressure, and reports position/state/completion to the audio handler,
// which drives the media session and queue from it.

import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';

import '../../core/utils/error_logger.dart';
import '../../domain/models/audio_quality_info.dart';
import '../services/usb_exclusive_service.dart';
import 'dsd_decoder_helper.dart';
import 'native_dsd_file_source.dart';
import 'native_dsd_producer.dart';
import 'playback_backend.dart';
import 'usb_hardware_volume_curve.dart';

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
  bool _nativeStatusActive = false;
  bool _fallbackFired = false;
  bool _prepared = false;
  bool _disposed = false;
  double _lastVolume = 1.0;

  /// Called once when the first real DSD block reaches the sink. Status must
  /// only claim native DSD from this point on.
  void Function()? onNativeActive;

  /// Called once when the stream died and the handler must reload the same
  /// track through DoP/PCM. The current position is supplied for resume.
  void Function(Duration position)? onFallbackRequired;

  final Future<DsdDacCapabilities> Function()? capabilitiesProvider;

  NativeDsdSession({
    UsbExclusiveService? usb,
    NativeDsdProducer? producer,
    this.capabilitiesProvider,
  })  : usbService = usb ?? UsbExclusiveService(),
        producer = producer ?? NativeDsdProducer();

  void setHardwareVolumeEnabled(bool enabled) {
    _hardwareVolumeEnabled = enabled;
  }

  bool get hardwareVolumeEnabled => _hardwareVolumeEnabled;

  /// Native DSD cannot be scaled in the 1-bit domain. When the DAC's Feature
  /// Unit is not in use, the only honest policy is fixed volume.
  String get volumePolicy => _hardwareVolumeEnabled ? 'hardware' : 'fixed';

  bool get isPrepared => _prepared;
  bool get nativeStatusActive => _nativeStatusActive;
  bool get fallbackRequested => producer.fallbackRequested;
  Duration get position => producer.currentPosition;
  Duration get duration => producer.totalDuration;

  @override
  BackendCapabilities get capabilities => BackendCapabilities.localDsd;

  @override
  Future<void> prepare(MediaItem item, {MediaItem? next}) async {
    await preparePath(
      item.extras?['path'] as String? ?? item.id,
      title: item.title,
      initialPosition: Duration.zero,
      autoPlay: false,
      mediaItem: item,
    );
  }

  /// Prepares a file for native DSD playback.
  ///
  /// [autoPlay] starts real data immediately; otherwise the opened stream is
  /// kept alive with DSD silence until [play].
  Future<void> preparePath(
    String path, {
    String? title,
    Duration? initialPosition,
    bool autoPlay = false,
    MediaItem? mediaItem,
  }) async {
    if (_disposed) throw const DsdFallbackRequiredException('Session disposed');
    await _reset();

    // File-backed: header once, then stream blocks. No 150 MB in-memory cap,
    // so full-length DSD64/128/256 tracks are playable.
    final NativeDsdFileSource source;
    try {
      source = await NativeDsdFileSource.open(path);
    } on DsdUnsupportedException catch (e) {
      throw DsdFallbackRequiredException(e.message);
    } on FormatException catch (e) {
      throw DsdFallbackRequiredException(
          'Cannot parse DSD container: ${e.message}');
    } on FileSystemException catch (e) {
      throw DsdFallbackRequiredException('Cannot open DSD file: ${e.message}');
    }

    final dsdRate = source.dsdRate;
    final caps = await (capabilitiesProvider?.call() ??
        DsdDecoderHelper.probeDopCapabilities());
    final tuple = NativeDsdProducer.selectProbedTuple(caps, dsdRate);
    if (tuple == null) {
      await source.close();
      throw DsdFallbackRequiredException(
        'No exact UAC2 native DSD alternate setting tuple found for DSD$dsdRate',
      );
    }

    // Data first, then the device: an open stream never lacks a producer.
    producer.prepareSource(
      source,
      dsdRate: dsdRate,
      msbFirst: source.msbFirst,
    );

    final opened = await producer.openStream(tuple, strict: true);
    if (!opened) {
      await producer.stop();
      throw const DsdFallbackRequiredException(
        'Failed to claim UAC2 interface and activate native DSD alt setting',
      );
    }

    _prepared = true;
    _currentItem = mediaItem ??
        MediaItem(
          id: path,
          title: title ?? path.split(Platform.pathSeparator).last,
          duration: producer.totalDuration,
          extras: <String, dynamic>{'path': path},
        );
    if (initialPosition != null && initialPosition > Duration.zero) {
      producer.seek(initialPosition);
    }
    _durationController.add(producer.totalDuration);
    _positionController.add(producer.currentPosition);
    _emitState(AudioProcessingState.ready, playing: false);
    _startTimers();

    // Keep the DAC clocked while loaded. play() switches to real data.
    unawaited(
      producer.startPumping(startPaused: true).then((_) => _onPumpEnded()),
    );

    if (autoPlay) await play();
  }

  @override
  Future<void> play() async {
    if (_disposed || !_prepared) return;
    if (producer.state == NativeDsdProducerState.completed) {
      producer.seek(Duration.zero);
    }
    _startTimers();
    _emitState(AudioProcessingState.ready, playing: true);
    producer.resume();
  }

  @override
  Future<void> pause() async {
    if (_disposed || !_prepared) return;
    producer.pause();
    _stopPositionTimer();
    _emitState(AudioProcessingState.ready, playing: false);
  }

  @override
  Future<void> seek(Duration position) async {
    if (_disposed || !_prepared) return;
    producer.seek(position);
    _positionController.add(producer.currentPosition);
    _emitState(
      AudioProcessingState.ready,
      playing: producer.state == NativeDsdProducerState.streaming,
    );
  }

  @override
  Future<void> stop() async {
    await _reset();
    _emitState(AudioProcessingState.idle, playing: false);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _reset();
    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
    await _completedController.close();
  }

  @override
  Future<void> setVolume(double volume) async {
    _lastVolume = volume.isFinite ? volume.clamp(0.0, 1.0) : 1.0;
    if (!_hardwareVolumeEnabled) {
      // No software gain is possible in the 1-bit domain. The handler's
      // capability gate must show fixed volume; never silently scale nothing.
      return;
    }
    final status = usbService.lastStatus;
    final min = status.minVolumeDb;
    final max = status.maxVolumeDb;
    if (min == null || max == null || min > max) return;
    try {
      await usbService.setHardwareVolume(
        UsbHardwareVolumeCurve.dbFor(_lastVolume, minDb: min, maxDb: max),
      );
    } catch (e, st) {
      ErrorLogger.log('Native DSD hardware volume failed',
          error: e, stackTrace: st, category: 'NativeDsdSession');
    }
  }

  Future<void> _reset() async {
    _stopPositionTimer();
    _prepared = false;
    _fallbackFired = false;
    _currentItem = null;
    _nativeStatusActive = false;
    AudioQualityInfo.dsdNativeActive = false;
    try {
      await producer.stop();
    } catch (e, st) {
      ErrorLogger.log('Native DSD producer stop failed during reset',
          error: e, stackTrace: st, category: 'NativeDsdSession');
    }
  }

  void _startTimers() {
    _stopPositionTimer();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_disposed || !_prepared) return;
      _updateNativeStatus();
      if (!_positionController.isClosed) {
        _positionController.add(producer.currentPosition);
      }
    });
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  void _updateNativeStatus() {
    if (!_nativeStatusActive && producer.firstBlockWritten) {
      _nativeStatusActive = true;
      AudioQualityInfo.dsdNativeActive = true;
      AudioQualityInfo.dsdDopActive = false;
      onNativeActive?.call();
    }
    if (!_fallbackFired && producer.fallbackRequested) {
      _fallbackFired = true;
      _stopPositionTimer();
      AudioQualityInfo.dsdNativeActive = false;
      _emitState(AudioProcessingState.error, playing: false);
      onFallbackRequired?.call(producer.currentPosition);
    }
  }

  void _onPumpEnded() {
    if (_disposed || !_prepared) return;
    _updateNativeStatus();
    if (producer.fallbackRequested) return;
    if (producer.state == NativeDsdProducerState.completed) {
      _stopPositionTimer();
      _positionController.add(producer.totalDuration);
      _emitState(AudioProcessingState.completed, playing: false);
      if (!_completedController.isClosed) {
        _completedController.add(null);
      }
    }
  }

  void _emitState(AudioProcessingState processingState,
      {required bool playing}) {
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
