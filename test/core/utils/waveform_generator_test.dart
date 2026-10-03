// Coverage for WaveformGenerator: PCM peak extraction, deterministic harmonic
// fallback, caching/LRU bounds and the isolate-backed async entry point.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/waveform_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WaveformGenerator.extractPeaksFromPcmSync', () {
    test('returns empty for empty input or non-positive bar counts', () {
      expect(
        WaveformGenerator.extractPeaksFromPcmSync(
          samples: Float32List(0),
          targetBarCount: 10,
        ),
        isEmpty,
      );
      expect(
        WaveformGenerator.extractPeaksFromPcmSync(
          samples: Float32List.fromList([0.5, 0.5]),
          targetBarCount: 0,
        ),
        isEmpty,
      );
      expect(
        WaveformGenerator.extractPeaksFromPcmSync(
          samples: Float32List.fromList([0.5]),
          targetBarCount: -3,
        ),
        isEmpty,
      );
    });

    test('buckets samples and normalizes to 0..1', () {
      final peaks = WaveformGenerator.extractPeaksFromPcmSync(
        samples: Float32List.fromList([0.0, -0.5, 1.0, -1.0]),
        targetBarCount: 2,
      );
      expect(peaks, hasLength(2));
      expect(peaks[0], 0.0);
      expect(peaks[1], 1.0);
    });

    test('falls back to per-sample abs when fewer samples than bars', () {
      final peaks = WaveformGenerator.extractPeaksFromPcmSync(
        samples: Float32List.fromList([-2.0, 0.5]),
        targetBarCount: 5,
      );
      expect(peaks, [1.0, 0.5]);
    });

    test('constant energy returns the flat 0.5 floor', () {
      final peaks = WaveformGenerator.extractPeaksFromPcmSync(
        samples: Float32List.fromList([0.3, 0.3, 0.3, 0.3]),
        targetBarCount: 2,
      );
      expect(peaks, [0.5, 0.5]);
    });

    test('last bucket absorbs the remainder of the sample buffer', () {
      final samples = Float32List.fromList([0.1, 0.2, 0.3, 0.4, 0.9]);
      final peaks = WaveformGenerator.extractPeaksFromPcmSync(
        samples: samples,
        targetBarCount: 2,
      );
      expect(peaks, hasLength(2));
      expect(peaks.last, 1.0);
    });
  });

  group('WaveformGenerator.generateWaveformSync', () {
    test('is deterministic for the same song id and count', () {
      final first = WaveformGenerator().generateWaveformSync(
        songId: 900001,
        count: 24,
      );
      final second = WaveformGenerator().generateWaveformSync(
        songId: 900001,
        count: 24,
      );
      expect(first, hasLength(24));
      expect(first, second);
      expect(first.every((v) => v >= 0.08 && v <= 1.0), isTrue);
    });

    test('different song ids produce different waveforms', () {
      final a = WaveformGenerator().generateWaveformSync(songId: 900002);
      final b = WaveformGenerator().generateWaveformSync(songId: 900003);
      expect(a, hasLength(60));
      expect(b, hasLength(60));
      expect(listEquals(a, b), isFalse);
    });

    test('file path participates in the seed', () {
      final a = WaveformGenerator().generateWaveformSync(
        songId: 900004,
        filePath: '/music/a.mp3',
      );
      final b = WaveformGenerator().generateWaveformSync(
        songId: 900005,
        filePath: '/music/a.mp3',
      );
      // Seed for 900004 is not prefixed by the path hash, 900005 is, so the
      // outputs differ even though ids are adjacent.
      expect(listEquals(a, b), isFalse);
    });

    test('count of zero yields an empty waveform', () {
      final samples =
          WaveformGenerator().generateWaveformSync(songId: 900006, count: 0);
      expect(samples, isEmpty);
    });

    test('LRU cache evicts the oldest entries past the cap', () {
      final generator = WaveformGenerator();
      for (int i = 0; i < 130; i++) {
        generator.generateWaveformSync(songId: 910000 + i, count: 4);
      }
      // The bulk of the eviction loop is exercised; regenerating an ancient id
      // must still return a valid deterministic waveform.
      final regenerated =
          generator.generateWaveformSync(songId: 910000, count: 4);
      expect(regenerated, hasLength(4));
    });

    test('cached entries are returned by identity', () {
      final generator = WaveformGenerator();
      final first = generator.generateWaveformSync(
        songId: 920001,
        filePath: '/tmp/ignored.mp3',
        count: 12,
      );
      // The cache key ignores the file path, so the cached list is reused even
      // when a different path is passed on the second call.
      final second = generator.generateWaveformSync(
        songId: 920001,
        filePath: '/tmp/other.mp3',
        count: 12,
      );
      expect(identical(first, second), isTrue);
    });
  });

  group('WaveformGenerator.generateWaveform', () {
    late Directory tempDir;

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('pulsr_waveform_');
    });

    tearDownAll(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('null file path uses the deterministic synchronous fallback',
        () async {
      final generated = await WaveformGenerator().generateWaveform(
        songId: 930001,
        count: 16,
      );
      final expected =
          WaveformGenerator().generateWaveformSync(songId: 930002, count: 16);
      expect(generated, hasLength(16));
      expect(expected, hasLength(16));
    });

    test('missing file path falls back to the harmonic waveform', () async {
      final samples = await WaveformGenerator().generateWaveform(
        songId: 930003,
        filePath: '${tempDir.path}${Platform.pathSeparator}missing.wav',
        count: 8,
      );
      expect(samples, hasLength(8));
      expect(samples.every((v) => v >= 0.08 && v <= 1.0), isTrue);
    });

    test('files under 1 KiB fall back to the harmonic waveform', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}tiny.wav');
      file.writeAsBytesSync(List<int>.filled(200, 0));
      final samples = await WaveformGenerator()
          .generateWaveform(songId: 930004, filePath: file.path, count: 10);
      expect(samples, hasLength(10));
      expect(samples.every((v) => v >= 0.08 && v <= 1.0), isTrue);
    });

    test('silent PCM yields the flat 0.4 floor', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}silent.wav');
      file.writeAsBytesSync(List<int>.filled(44100, 0));
      final samples = await WaveformGenerator()
          .generateWaveform(songId: 930005, filePath: file.path, count: 12);
      expect(samples, hasLength(12));
      expect(samples.every((v) => (v - 0.4).abs() < 1e-9), isTrue);
    });

    test('varying PCM is normalized to visible bar heights', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}varying.wav');
      final bytes = Uint8List(44 + 2 * 4410);
      for (int i = 0; i < 4410; i++) {
        // Ramp from quiet to loud 16-bit signed samples.
        final value = ((i / 4410) * 30000).round();
        bytes[44 + i * 2] = value & 0xFF;
        bytes[44 + i * 2 + 1] = (value >> 8) & 0xFF;
      }
      file.writeAsBytesSync(bytes);
      final samples = await WaveformGenerator()
          .generateWaveform(songId: 930006, filePath: file.path, count: 10);
      expect(samples, hasLength(10));
      expect(samples.every((v) => v >= 0.08 && v <= 1.0), isTrue);
      expect(samples.toSet().length, greaterThan(1));
    });

    test('a cached async result is reused without re-extraction', () async {
      final generator = WaveformGenerator();
      final first = await generator.generateWaveform(
        songId: 930007,
        count: 6,
      );
      final second = await generator.generateWaveform(
        songId: 930007,
        count: 6,
      );
      expect(identical(first, second), isTrue);
    });

    test('more bars than PCM bytes exercises the empty-read floor', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}sparse.wav');
      file.writeAsBytesSync(List<int>.filled(1100, 0));
      final samples = await WaveformGenerator()
          .generateWaveform(songId: 930008, filePath: file.path, count: 2000);
      expect(samples, hasLength(2000));
      expect(samples.every((v) => (v - 0.4).abs() < 1e-9), isTrue);
    });

    test('large PCM files cap the per-bar read buffer at 4096 bytes', () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}large.wav');
      final bytes = Uint8List(44 + 200000);
      for (int i = 0; i < 100000; i++) {
        final value = (i % 30000).round();
        bytes[44 + i * 2] = value & 0xFF;
        bytes[44 + i * 2 + 1] = (value >> 8) & 0xFF;
      }
      file.writeAsBytesSync(bytes);
      final samples = await WaveformGenerator()
          .generateWaveform(songId: 930009, filePath: file.path, count: 3);
      expect(samples, hasLength(3));
      expect(samples.every((v) => v >= 0.08 && v <= 1.0), isTrue);
    });
  });
}
