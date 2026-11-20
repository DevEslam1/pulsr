// lib/data/audio/native_dsd_producer.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../services/usb_exclusive_service.dart';
import 'dsd_decoder_helper.dart';

/// Transport state of the native DSD producer.
enum NativeDsdProducerState {
  idle,
  streaming,
  paused,
  stopped,
  completed,
}

/// Dedicated producer that streams raw 1-bit DSD audio blocks directly
/// to a UAC2 USB DAC in DSD_U32 native mode with backpressure handling.
class NativeDsdProducer {
  final UsbExclusiveService usbService;

  NativeDsdProducer({UsbExclusiveService? service})
      : usbService = service ?? UsbExclusiveService();

  NativeDsdProducerState _state = NativeDsdProducerState.idle;
  NativeDsdProducerState get state => _state;
  bool get isRunning =>
      _state == NativeDsdProducerState.streaming ||
      _state == NativeDsdProducerState.paused;
  bool get isPaused => _state == NativeDsdProducerState.paused;

  Uint8List? _dsdLeft;
  Uint8List? _dsdRight;
  int _dsdRate = 0;
  int _sampleRate = 0;
  int _currentByteOffset = 0;
  int _totalBytes = 0;
  DsdAltSettingTuple? _activeTuple;

  DsdAltSettingTuple? get activeTuple => _activeTuple;
  int get dsdRate => _dsdRate;
  int get currentByteOffset => _currentByteOffset;
  int get totalBytes => _totalBytes;

  Completer<void>? _pauseCompleter;
  bool _stopRequested = false;

  /// Chunk size per channel per write (16 KB = ~46 ms at DSD64).
  static const int kDefaultChunkBytes = 16384;

  /// Backpressure sleep duration when the sink ring buffer is full.
  static const Duration kBackpressureDelay = Duration(milliseconds: 5);

  /// Maximum consecutive backpressure retries before checking stream health.
  static const int kMaxBackpressureRetries = 200; // ~1 second

  /// Selects the probed UAC2 DSD alternate setting tuple that matches [dsdRate].
  static DsdAltSettingTuple? selectProbedTuple(
    DsdDacCapabilities caps,
    int dsdRate,
  ) {
    if (!caps.dacSupportsNativeDsd || caps.nativeAltSettings.isEmpty) {
      return null;
    }
    for (final tuple in caps.nativeAltSettings) {
      if (tuple.dsdRate == dsdRate) return tuple;
    }
    for (final tuple in caps.nativeAltSettings) {
      if (tuple.framesPerSecond > 0) return tuple;
    }
    return null;
  }

  /// Opens the native DSD stream on the DAC for [tuple].
  Future<bool> openStream(DsdAltSettingTuple tuple,
      {bool strict = true}) async {
    final ok = await usbService.startDsdStreaming(tuple, strict: strict);
    if (ok) {
      _activeTuple = tuple;
    }
    return ok;
  }

  /// Prepares the producer with decoded DSD buffers.
  void prepare({
    required Uint8List left,
    required Uint8List right,
    required int dsdRate,
    bool msbFirst = false,
  }) {
    var l = left;
    var r = right;
    if (msbFirst) {
      l = reverseBits(l);
      r = reverseBits(r);
    }
    final minLen = math.min(l.length, r.length);
    _dsdLeft = Uint8List.sublistView(l, 0, minLen);
    _dsdRight = Uint8List.sublistView(r, 0, minLen);
    _dsdRate = dsdRate;
    _sampleRate = (dsdRate > 0 ? dsdRate : 64) * 44100;
    _totalBytes = minLen;
    _currentByteOffset = 0;
    _stopRequested = false;
    _state = NativeDsdProducerState.idle;
  }

  /// Starts or resumes pumping DSD blocks with backpressure.
  Future<void> startPumping({int chunkSize = kDefaultChunkBytes}) async {
    if (_dsdLeft == null || _dsdRight == null) return;
    _state = NativeDsdProducerState.streaming;
    _stopRequested = false;

    while (!_stopRequested && _currentByteOffset < _totalBytes) {
      if (_state == NativeDsdProducerState.paused) {
        _pauseCompleter = Completer<void>();
        await _pauseCompleter!.future;
        if (_stopRequested) break;
      }

      final remaining = _totalBytes - _currentByteOffset;
      final currentChunk = math.min(chunkSize, remaining);
      if (currentChunk <= 0) break;

      final chunkL = Uint8List.sublistView(
          _dsdLeft!, _currentByteOffset, _currentByteOffset + currentChunk);
      final chunkR = Uint8List.sublistView(
          _dsdRight!, _currentByteOffset, _currentByteOffset + currentChunk);

      int retries = 0;
      bool written = false;
      while (!_stopRequested && !written) {
        written = await usbService.writeDsd(chunkL, chunkR);
        if (!written) {
          retries++;
          if (retries > kMaxBackpressureRetries) {
            final active = await usbService.isDsdActive();
            if (!active) {
              _state = NativeDsdProducerState.stopped;
              return;
            }
          }
          await Future<void>.delayed(kBackpressureDelay);
        }
      }

      if (written) {
        _currentByteOffset += currentChunk;
      }
    }

    if (_stopRequested) {
      _state = NativeDsdProducerState.stopped;
    } else if (_currentByteOffset >= _totalBytes) {
      _state = NativeDsdProducerState.completed;
    }
  }

  /// Pauses pumping.
  void pause() {
    if (_state == NativeDsdProducerState.streaming) {
      _state = NativeDsdProducerState.paused;
    }
  }

  /// Resumes pumping after pause.
  void resume() {
    if (_state == NativeDsdProducerState.paused) {
      _state = NativeDsdProducerState.streaming;
      _pauseCompleter?.complete();
      _pauseCompleter = null;
    }
  }

  /// Seeks to a specific track duration.
  void seek(Duration position) {
    if (_sampleRate <= 0 || _totalBytes <= 0) return;
    final targetBits = (position.inMicroseconds * _sampleRate) ~/ 1000000;
    var targetByte = targetBits ~/ 8;
    // Align to 4-byte boundary for 32-bit DSD_U32 words
    targetByte = (targetByte ~/ 4) * 4;
    _currentByteOffset = targetByte.clamp(0, _totalBytes);
  }

  /// Stops streaming and releases the USB sink.
  Future<void> stop() async {
    _stopRequested = true;
    _state = NativeDsdProducerState.stopped;
    _pauseCompleter?.complete();
    _pauseCompleter = null;
    try {
      await usbService.stopStreaming();
    } catch (_) {}
  }

  Duration get currentPosition {
    if (_sampleRate <= 0) return Duration.zero;
    final bits = _currentByteOffset * 8;
    final us = (bits * 1000000) ~/ _sampleRate;
    return Duration(microseconds: us);
  }

  Duration get totalDuration {
    if (_sampleRate <= 0) return Duration.zero;
    final bits = _totalBytes * 8;
    final us = (bits * 1000000) ~/ _sampleRate;
    return Duration(microseconds: us);
  }

  /// Reverses bits within each byte (MSB-first to LSB-first).
  static Uint8List reverseBits(Uint8List input) {
    final out = Uint8List(input.length);
    for (int i = 0; i < input.length; ++i) {
      int b = input[i];
      b = ((b & 0xF0) >> 4) | ((b & 0x0F) << 4);
      b = ((b & 0xCC) >> 2) | ((b & 0x33) << 2);
      b = ((b & 0xAA) >> 1) | ((b & 0x55) << 1);
      out[i] = b;
    }
    return out;
  }
}
