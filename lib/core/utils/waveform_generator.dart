// lib/core/utils/waveform_generator.dart
import 'dart:collection';
import 'dart:io';
import 'dart:math';

/// Generates downsampled audio waveform samples (0.0 to 1.0) per song ID with LRU caching.
class WaveformGenerator {
  static final WaveformGenerator _instance = WaveformGenerator._internal();
  factory WaveformGenerator() => _instance;
  WaveformGenerator._internal();

  static const int _maxCacheSize = 100;
  final LinkedHashMap<String, List<double>> _cache = LinkedHashMap();

  /// Computes or retrieves cached waveform samples for a given [songId].
  Future<List<double>> generateWaveform({
    required int songId,
    String? filePath,
    int count = 60,
  }) async {
    final cacheKey = '${songId}_$count';

    // 1. Check LRU Cache
    if (_cache.containsKey(cacheKey)) {
      final cachedSamples = _cache.remove(cacheKey)!;
      _cache[cacheKey] = cachedSamples; // Refresh LRU position
      return cachedSamples;
    }

    List<double> samples = [];

    // 2. Attempt file-based sample extraction
    if (filePath != null && filePath.isNotEmpty) {
      try {
        samples = await _extractFromFile(filePath, count);
      } catch (_) {
        samples = [];
      }
    }

    // 3. Fallback to deterministic harmonic waveform if file extraction returns empty
    if (samples.isEmpty || samples.length != count) {
      samples = _generateDeterministicWaveform(songId, count);
    }

    // 4. Cache result with LRU eviction
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[cacheKey] = samples;

    return samples;
  }

  /// Synchronously returns cached waveform samples if present.
  List<double>? getCachedWaveform({required int songId, int count = 60}) {
    final cacheKey = '${songId}_$count';
    if (_cache.containsKey(cacheKey)) {
      final cachedSamples = _cache.remove(cacheKey)!;
      _cache[cacheKey] = cachedSamples;
      return cachedSamples;
    }
    return null;
  }

  /// Clears the LRU waveform cache.
  void clearCache() {
    _cache.clear();
  }

  Future<List<double>> _extractFromFile(String path, int count) async {
    final file = File(path);
    if (!await file.exists()) return [];

    final fileSize = await file.length();
    if (fileSize < 1024) return [];

    final RandomAccessFile raf = await file.open(mode: FileMode.read);
    final List<double> rawEnergies = [];

    try {
      final double step = (fileSize - 512) / count;
      final int chunkSize = 512;

      for (int i = 0; i < count; i++) {
        final int position = (i * step).clamp(0, fileSize - chunkSize).toInt();
        await raf.setPosition(position);
        final bytes = await raf.read(chunkSize);

        if (bytes.isEmpty) {
          rawEnergies.add(0.1);
          continue;
        }

        // Compute RMS energy of sample byte values
        double sumSq = 0;
        for (int b in bytes) {
          final double normalizedVal = (b - 128) / 128.0;
          sumSq += normalizedVal * normalizedVal;
        }
        final double rms = sqrt(sumSq / bytes.length);
        rawEnergies.add(rms);
      }
    } finally {
      await raf.close();
    }

    return _normalizeSamples(rawEnergies);
  }

  List<double> _generateDeterministicWaveform(int songId, int count) {
    final List<double> raw = [];
    final Random random = Random(songId);

    final double seed1 = random.nextDouble() * 10.0;
    final double seed2 = random.nextDouble() * 10.0;
    final double seed3 = random.nextDouble() * 10.0;

    for (int i = 0; i < count; i++) {
      final double t = i / count;

      // Multi-frequency harmonic combination
      double val = sin(t * pi * 8 + seed1) * 0.4 +
          cos(t * pi * 14 + seed2) * 0.3 +
          sin(t * pi * 3 + seed3) * 0.3 +
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

    return _normalizeSamples(raw);
  }

  List<double> _normalizeSamples(List<double> raw) {
    if (raw.isEmpty) return [];

    double minVal = raw.reduce(min);
    double maxVal = raw.reduce(max);
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
}
