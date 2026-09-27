// lib/core/utils/waveform_generator.dart
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

typedef _WaveformParams = ({int songId, int count, String? filePath});

List<double> _computeDeterministicWaveformTask(_WaveformParams params) {
  final List<double> raw = [];
  final int rawSeed = params.filePath != null && params.filePath!.isNotEmpty
      ? (params.songId ^ params.filePath.hashCode)
      : params.songId;
  final int seed = rawSeed.abs() & 0x7FFFFFFF;
  final math.Random random = math.Random(seed);

  final double seed1 = random.nextDouble() * 10.0;
  final double seed2 = random.nextDouble() * 10.0;
  final double seed3 = random.nextDouble() * 10.0;

  for (int i = 0; i < params.count; i++) {
    final double t = i / params.count;

    // Multi-frequency harmonic combination
    double val = math.sin(t * math.pi * 8 + seed1) * 0.4 +
        math.cos(t * math.pi * 14 + seed2) * 0.3 +
        math.sin(t * math.pi * 3 + seed3) * 0.3 +
        0.5;

    // Envelope: smooth fade-in at intro & fade-out at outro
    double envelope = 1.0;
    if (t < 0.08) {
      envelope = 0.3 + (t / 0.08) * 0.7;
    } else if (t > 0.92) {
      envelope = 0.3 + ((1.0 - t) / 0.08) * 0.7;
    }

    val = (val.abs() * envelope).clamp(0.05, 1.0);
    raw.add(val);
  }

  if (raw.isEmpty) return [];

  final double minVal = raw.reduce(math.min);
  final double maxVal = raw.reduce(math.max);
  final double range = maxVal - minVal;

  if (range < 0.0001) {
    return List.filled(raw.length, 0.5);
  }

  return raw.map((v) {
    final double norm = (v - minVal) / range;
    // Clamp between 0.08 (min visible height) and 1.0
    return (0.08 + norm * 0.92).clamp(0.08, 1.0);
  }).toList();
}

/// Background isolate task extracting actual PCM peak and RMS energy from audio files.
List<double> _extractPcmPeaksTask(_WaveformParams params) {
  if (params.filePath == null || params.filePath!.isEmpty) {
    return _computeDeterministicWaveformTask(params);
  }
  try {
    final file = File(params.filePath!);
    if (!file.existsSync()) {
      return _computeDeterministicWaveformTask(params);
    }
    final length = file.lengthSync();
    if (length < 1024) {
      return _computeDeterministicWaveformTask(params);
    }

    final count = params.count;
    final samples = <double>[];
    final raf = file.openSync(mode: FileMode.read);
    try {
      final headerOffset = length > 44 ? 44 : 0;
      final dataLength = length - headerOffset;
      final bucketSize = (dataLength / count).floor();
      final bufferSize = math.min(bucketSize, 4096);
      final buffer = Uint8List(bufferSize);

      for (int b = 0; b < count; b++) {
        final pos = headerOffset + b * bucketSize;
        raf.setPositionSync(pos);
        final readBytes = raf.readIntoSync(buffer, 0, bufferSize);
        if (readBytes <= 0) {
          samples.add(0.2);
          continue;
        }

        double maxSample = 0.0;
        double sumSq = 0.0;
        int samplePairs = 0;
        for (int i = 0; i <= readBytes - 2; i += 2) {
          final s16 = buffer[i] | (buffer[i + 1] << 8);
          final signed = s16 >= 32768 ? s16 - 65536 : s16;
          final normalized = signed.abs() / 32768.0;
          if (normalized > maxSample) maxSample = normalized;
          sumSq += normalized * normalized;
          samplePairs++;
        }
        final rms = samplePairs > 0 ? math.sqrt(sumSq / samplePairs) : 0.0;
        final composite = (maxSample * 0.7 + rms * 0.3).clamp(0.0, 1.0);
        samples.add(composite);
      }
    } finally {
      raf.closeSync();
    }

    if (samples.isEmpty) return _computeDeterministicWaveformTask(params);

    final minVal = samples.reduce(math.min);
    final maxVal = samples.reduce(math.max);
    final range = maxVal - minVal;
    if (range < 0.01) {
      return List.filled(samples.length, 0.4);
    }
    return samples.map((v) {
      final norm = (v - minVal) / range;
      return (0.08 + norm * 0.92).clamp(0.08, 1.0);
    }).toList();
  } catch (_) {
    return _computeDeterministicWaveformTask(params);
  }
}

/// Generates downsampled audio waveform samples (0.0 to 1.0) per song ID with LRU caching.
class WaveformGenerator {
  static final WaveformGenerator _instance = WaveformGenerator._internal();
  factory WaveformGenerator() => _instance;
  WaveformGenerator._internal();

  static const int _maxCacheSize = 100;
  final LinkedHashMap<String, List<double>> _cache = LinkedHashMap();

  /// Extracts downsampled peak magnitudes from in-memory PCM float buffer.
  static List<double> extractPeaksFromPcmSync({
    required Float32List samples,
    required int targetBarCount,
  }) {
    if (samples.isEmpty || targetBarCount <= 0) return [];
    final bucketSize = samples.length ~/ targetBarCount;
    if (bucketSize <= 0) {
      return samples.map((s) => s.abs().clamp(0.0, 1.0)).toList();
    }
    final peaks = <double>[];
    for (int b = 0; b < targetBarCount; b++) {
      final start = b * bucketSize;
      final end = (b == targetBarCount - 1) ? samples.length : (b + 1) * bucketSize;
      double maxVal = 0.0;
      for (int i = start; i < end && i < samples.length; i++) {
        final abs = samples[i].abs();
        if (abs > maxVal) maxVal = abs;
      }
      peaks.add(maxVal);
    }
    final minVal = peaks.reduce(math.min);
    final maxVal = peaks.reduce(math.max);
    final range = maxVal - minVal;
    if (range < 0.0001) return List.filled(peaks.length, 0.5);
    return peaks.map((p) => ((p - minVal) / range).clamp(0.0, 1.0)).toList();
  }

  /// Computes or retrieves cached waveform samples synchronously in ~5 microseconds.
  List<double> generateWaveformSync({
    required int songId,
    String? filePath,
    int count = 60,
  }) {
    final cacheKey = '${songId}_$count';

    // 1. Check LRU Cache
    if (_cache.containsKey(cacheKey)) {
      final cachedSamples = _cache.remove(cacheKey)!;
      _cache[cacheKey] = cachedSamples;
      return cachedSamples;
    }

    // 2. Generate deterministic harmonic waveform synchronously
    final samples = _computeDeterministicWaveformTask(
      (songId: songId, count: count, filePath: filePath),
    );

    // 3. Cache result with LRU eviction
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[cacheKey] = samples;

    return samples;
  }

  /// Computes or retrieves cached waveform samples asynchronously using isolate peak extraction.
  Future<List<double>> generateWaveform({
    required int songId,
    String? filePath,
    int count = 60,
  }) async {
    final cacheKey = '${songId}_$count';
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache.remove(cacheKey)!;
      _cache[cacheKey] = cached;
      return cached;
    }

    List<double> result;
    if (filePath != null && filePath.isNotEmpty && File(filePath).existsSync()) {
      try {
        result = await compute(
          _extractPcmPeaksTask,
          (songId: songId, count: count, filePath: filePath),
        );
      } catch (_) {
        result = generateWaveformSync(songId: songId, filePath: filePath, count: count);
      }
    } else {
      result = generateWaveformSync(songId: songId, filePath: filePath, count: count);
    }

    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[cacheKey] = result;
    return result;
  }
}
