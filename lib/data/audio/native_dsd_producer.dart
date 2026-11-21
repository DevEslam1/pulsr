// lib/data/audio/native_dsd_producer.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/utils/error_logger.dart';
import '../services/usb_exclusive_service.dart';
import 'dsd_decoder_helper.dart';
import 'native_dsd_file_source.dart';

/// Transport state of the native DSD producer.
enum NativeDsdProducerState {
  idle,
  streaming,
  paused,
  stopped,
  completed,
}

/// Streams raw 1-bit DSD blocks to a UAC2 DAC in DSD_U32 native mode.
///
/// One pump loop owns the stream for its lifetime. Pause does not tear the
/// stream down: it keeps the sink fed with the DC-neutral DSD silence pattern,
/// so the DAC clock stays locked and resume has no underrun. The sink's own
/// ring buffer is the pacing element; a rejected write is backpressure, not an
/// xrun, and never loses data.
class NativeDsdProducer {
  final UsbExclusiveService usbService;
  final Duration backpressureDelay;

  NativeDsdProducer({
    UsbExclusiveService? service,
    this.backpressureDelay = kBackpressureDelay,
  }) : usbService = service ?? UsbExclusiveService();

  NativeDsdProducerState _state = NativeDsdProducerState.idle;
  NativeDsdProducerState get state => _state;
  bool get isRunning =>
      _state == NativeDsdProducerState.streaming ||
      _state == NativeDsdProducerState.paused;
  bool get isPaused => _state == NativeDsdProducerState.paused;
  bool get isPumping => _pumpFuture != null;

  Uint8List? _dsdLeft;
  Uint8List? _dsdRight;
  NativeDsdFileSource? _source;
  bool _sourceMsbFirst = false;
  int _dsdRate = 0;
  int _sampleRate = 0;
  int _currentByteOffset = 0;
  int _totalBytes = 0;
  int _xrunCount = 0;
  DsdAltSettingTuple? _activeTuple;
  int _chunkSize = kDefaultChunkBytes;
  bool _firstBlockWritten = false;
  bool _fallbackRequested = false;

  DsdAltSettingTuple? get activeTuple => _activeTuple;
  int get dsdRate => _dsdRate;
  int get currentByteOffset => _currentByteOffset;
  int get totalBytes => _totalBytes;
  int get xrunCount => _xrunCount;

  /// True only after the sink accepted the first real (non-silence) block.
  /// Status must not claim native DSD before this flips.
  bool get firstBlockWritten => _firstBlockWritten;

  /// Set when the stream died and the caller must fall back to DoP/PCM.
  bool get fallbackRequested => _fallbackRequested;

  Future<void>? _pumpFuture;
  bool _stopRequested = false;
  int _seekGeneration = 0;
  void Function()? onPumpEnded;

  /// Chunk size per channel per write (16 KB = ~46 ms at DSD64).
  static const int kDefaultChunkBytes = 16384;

  /// Backpressure sleep duration when the sink ring buffer is full.
  static const Duration kBackpressureDelay = Duration(milliseconds: 5);

  /// Maximum consecutive backpressure retries before checking stream health.
  static const int kMaxBackpressureRetries = 200; // ~1 second

  /// Maximum stream-death events before halting for fallback (§8.2).
  static const int kMaxXrunsBeforeFallback = 10;

  /// DC-neutral DSD silence pattern: alternating 0x69 / 0x96 bytes (§8.2).
  static Uint8List dsdSilenceBlock(int length) {
    final block = Uint8List(length);
    for (int i = 0; i < length; i++) {
      block[i] = i.isEven ? 0x69 : 0x96;
    }
    return block;
  }

  /// Selects the probed UAC2 DSD alternate setting tuple that matches [dsdRate].
  /// Enforces exact tuple selection without first-tuple fallback (§8.2).
  static DsdAltSettingTuple? selectProbedTuple(
    DsdDacCapabilities caps,
    int dsdRate,
  ) {
    if (!caps.dacSupportsNativeDsd ||
        caps.nativeAltSettings.isEmpty ||
        dsdRate <= 0) {
      return null;
    }
    for (final tuple in caps.nativeAltSettings) {
      if (tuple.dsdRate == dsdRate) return tuple;
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

  /// Prepares the producer with decoded DSD buffers. Must run before
  /// [openStream] so a failed open never leaves a stream without data.
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
    _source = null;
    _sourceMsbFirst = false;
    _dsdLeft = Uint8List.sublistView(l, 0, minLen);
    _dsdRight = Uint8List.sublistView(r, 0, minLen);
    _dsdRate = dsdRate;
    _sampleRate = (dsdRate > 0 ? dsdRate : 64) * 44100;
    _totalBytes = minLen;
    _currentByteOffset = 0;
    _xrunCount = 0;
    _firstBlockWritten = false;
    _fallbackRequested = false;
    _stopRequested = false;
    _seekGeneration++;
    _state = NativeDsdProducerState.idle;
  }

  /// Prepares a file-backed stream. The producer takes ownership of [source];
  /// [stop] closes it. This path has no in-memory size cap, so full-length
  /// DSD64/256 tracks stream instead of being rejected.
  void prepareSource(
    NativeDsdFileSource source, {
    required int dsdRate,
    required bool msbFirst,
  }) {
    _source = source;
    _sourceMsbFirst = msbFirst;
    _dsdLeft = null;
    _dsdRight = null;
    _dsdRate = dsdRate;
    _sampleRate = (dsdRate > 0 ? dsdRate : 64) * 44100;
    _totalBytes = source.totalBytes;
    _currentByteOffset = source.position;
    _xrunCount = 0;
    _firstBlockWritten = false;
    _fallbackRequested = false;
    _stopRequested = false;
    _seekGeneration++;
    _state = NativeDsdProducerState.idle;
  }

  /// Starts or resumes the single pump loop. Idempotent while pumping.
  ///
  /// [startPaused] keeps the opened stream alive with DSD silence until the
  /// caller plays, so a loaded-but-paused track never underruns the DAC.
  Future<void> startPumping({
    int chunkSize = kDefaultChunkBytes,
    bool startPaused = false,
  }) {
    _chunkSize = chunkSize.clamp(1, kDefaultChunkBytes);
    if (_source == null && (_dsdLeft == null || _dsdRight == null)) {
      return Future<void>.value();
    }
    final existing = _pumpFuture;
    if (existing != null) return existing;
    _stopRequested = false;
    if (_state == NativeDsdProducerState.idle ||
        _state == NativeDsdProducerState.stopped ||
        _state == NativeDsdProducerState.completed) {
      _state = startPaused
          ? NativeDsdProducerState.paused
          : NativeDsdProducerState.streaming;
    }
    final future = _runPump();
    _pumpFuture = future.whenComplete(() {
      _pumpFuture = null;
    });
    return _pumpFuture!;
  }

  Future<void> _runPump() async {
    final silence = dsdSilenceBlock(_chunkSize);
    try {
      while (!_stopRequested) {
        if (_state == NativeDsdProducerState.paused) {
          // Keep the alt setting fed so the DAC clock stays locked. Pace the
          // silence at the DSD byte rate: a sink that accepts writes instantly
          // must not turn pause into a busy loop.
          final ok = await _writeWithRetry(silence, silence);
          if (!ok) break;
          final us = _sampleRate > 0
              ? (_chunkSize * 8 * 1000000) ~/ _sampleRate
              : 20000;
          if (!_stopRequested) {
            await Future<void>.delayed(
              Duration(microseconds: us.clamp(1000, 100000)),
            );
          }
          continue;
        }
        if (_state == NativeDsdProducerState.stopped ||
            _state == NativeDsdProducerState.completed) {
          break;
        }
        final loopGen = _seekGeneration;
        final Uint8List chunkL;
        final Uint8List chunkR;
        if (_source != null) {
          final chunk = await _source!.readChunk(_chunkSize);
          if (loopGen != _seekGeneration) continue;
          if (chunk == null) {
            _state = NativeDsdProducerState.completed;
            break;
          }
          chunkL =
              _sourceMsbFirst ? reverseBits(chunk.left) : chunk.left;
          chunkR =
              _sourceMsbFirst ? reverseBits(chunk.right) : chunk.right;
        } else {
          final offset = _currentByteOffset;
          final remaining = _totalBytes - offset;
          if (remaining <= 0) {
            _state = NativeDsdProducerState.completed;
            break;
          }
          final currentChunk = math.min(_chunkSize, remaining);
          chunkL = Uint8List.sublistView(
              _dsdLeft!, offset, offset + currentChunk);
          chunkR = Uint8List.sublistView(
              _dsdRight!, offset, offset + currentChunk);
        }
        final ok = await _writeWithRetry(chunkL, chunkR);
        if (!ok) break;
        if (loopGen == _seekGeneration) {
          _currentByteOffset += chunkL.length;
        }
        _firstBlockWritten = true;
      }
    } finally {
      _pumpFuture = null;
      if (_stopRequested) {
        _state = NativeDsdProducerState.stopped;
      }
      onPumpEnded?.call();
    }
  }

  Future<bool> _writeWithRetry(Uint8List left, Uint8List right) async {
    int retries = 0;
    while (!_stopRequested) {
      final written = await usbService.writeDsd(left, right);
      if (written) return true;
      retries++;
      if (retries > kMaxBackpressureRetries) {
        _xrunCount++;
        if (_xrunCount >= kMaxXrunsBeforeFallback) {
          _fallbackRequested = true;
          _state = NativeDsdProducerState.stopped;
          return false;
        }
        final active = await usbService.isDsdActive();
        if (!active) {
          _fallbackRequested = true;
          _state = NativeDsdProducerState.stopped;
          return false;
        }
        retries = 0;
      }
      await Future<void>.delayed(backpressureDelay);
    }
    return false;
  }

  /// Keeps the stream alive with DSD silence. No-op before streaming, matching
  /// the transport contract: a loaded-but-not-started producer stays idle.
  void pause() {
    if (_state == NativeDsdProducerState.streaming) {
      _state = NativeDsdProducerState.paused;
      unawaited(startPumping(chunkSize: _chunkSize));
    }
  }

  /// Resumes real data after a pause.
  void resume() {
    if (_state == NativeDsdProducerState.paused ||
        _state == NativeDsdProducerState.idle) {
      _state = NativeDsdProducerState.streaming;
      unawaited(startPumping(chunkSize: _chunkSize));
    }
  }

  /// Seeks to [position]. Alignment is to the 4-byte DSD_U32 word so the
  /// native packer never starts mid-word.
  void seek(Duration position) {
    if (_sampleRate <= 0 || _totalBytes <= 0) return;
    _seekGeneration++;
    final targetBits = (position.inMicroseconds * _sampleRate) ~/ 1000000;
    var targetByte = targetBits ~/ 8;
    targetByte = (targetByte ~/ 4) * 4;
    _currentByteOffset = targetByte.clamp(0, _totalBytes);
    _source?.seek(_currentByteOffset);
    if (_state == NativeDsdProducerState.completed &&
        _currentByteOffset < _totalBytes) {
      _state = NativeDsdProducerState.paused;
    }
  }

  /// Stops the loop, then releases the USB stream.
  Future<void> stop() async {
    _stopRequested = true;
    _state = NativeDsdProducerState.stopped;
    final future = _pumpFuture;
    if (future != null) {
      try {
        await future.timeout(const Duration(seconds: 2));
      } catch (e, st) {
        ErrorLogger.log('Native DSD pump did not stop in time',
            error: e, stackTrace: st, category: 'NativeDsdProducer');
      }
    }
    try {
      await usbService.stopStreaming();
    } catch (e, st) {
      ErrorLogger.log('Native DSD stream release failed',
          error: e, stackTrace: st, category: 'NativeDsdProducer');
    }
    final source = _source;
    _source = null;
    if (source != null) {
      try {
        await source.close();
      } catch (e, st) {
        ErrorLogger.log('Native DSD file close failed',
            error: e, stackTrace: st, category: 'NativeDsdProducer');
      }
    }
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
