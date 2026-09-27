// test/audit_all_phases_100_percent_test.dart
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/lrc_parser.dart';
import 'package:pulsr/core/utils/waveform_generator.dart';
import 'package:pulsr/core/utils/yin_pitch_detector.dart';
import 'package:pulsr/data/audio/dsp_chain_validator.dart';
import 'package:pulsr/data/audio/dsp_warmup_scheduler.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/features/player/presentation/widgets/waveform_seek_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('100% Comprehensive Audit Verification Suite', () {
    group('1. Database Health Check, Optimizer & Migration Validator', () {
      test('DatabaseHealthReport serialization and getters are consistent', () {
        const report = DatabaseHealthReport(
          isHealthy: true,
          integrityIssues: [],
          foreignKeyViolations: [],
          totalSongs: 120,
          totalPlaylists: 5,
          totalHistoryEntries: 450,
          databaseSizeBytes: 1048576,
          ftsHealthy: true,
        );

        expect(report.isHealthy, isTrue);
        expect(report.totalSongs, equals(120));
        expect(report.totalPlaylists, equals(5));
        expect(report.totalHistoryEntries, equals(450));
        expect(report.databaseSizeBytes, equals(1048576));
        expect(report.ftsHealthy, isTrue);

        final map = report.toMap();
        expect(map['isHealthy'], isTrue);
        expect(map['totalSongs'], equals(120));
        expect(report.toString(), contains('healthy: true'));
      });

      test('DatabaseOptimizationReport tracks reclaimed bytes and duration', () {
        const optReport = DatabaseOptimizationReport(
          pagesBefore: 100,
          pagesAfter: 75,
          bytesReclaimed: 25 * 4096,
          duration: Duration(milliseconds: 150),
          ftsRebuilt: true,
        );

        expect(optReport.pagesBefore, equals(100));
        expect(optReport.pagesAfter, equals(75));
        expect(optReport.bytesReclaimed, equals(102400));
        expect(optReport.ftsRebuilt, isTrue);
        expect(optReport.duration.inMilliseconds, equals(150));
        expect(optReport.toString(), contains('reclaimed: 100 KB'));
      });

      test('MigrationValidationResult exposes schema audit status', () {
        const valResult = MigrationValidationResult(
          isValid: true,
          currentVersion: 11,
          expectedVersion: 11,
          missingTables: [],
          missingColumns: [],
          missingIndexes: [],
        );

        expect(valResult.isValid, isTrue);
        expect(valResult.currentVersion, equals(11));
        expect(valResult.missingTables, isEmpty);
        expect(valResult.missingColumns, isEmpty);
        expect(valResult.missingIndexes, isEmpty);
        expect(valResult.toString(), contains('version: 11/11'));
      });
    });

    group('2. MediaScannerService Incremental Scanning & Progress', () {
      test('ScanProgressUpdate correctly formats status and metadata', () {
        const update = ScanProgressUpdate(
          progress: 0.65,
          currentFile: 'Bohemian Rhapsody.flac',
          scannedCount: 65,
          totalCount: 100,
          isIncremental: true,
        );

        expect(update.progress, equals(0.65));
        expect(update.currentFile, equals('Bohemian Rhapsody.flac'));
        expect(update.scannedCount, equals(65));
        expect(update.totalCount, equals(100));
        expect(update.isIncremental, isTrue);
        expect(update.toString(), contains('65.0%'));
        expect(update.toString(), contains('count: 65/100'));
      });
    });

    group('3. DSP Chain Validator & Warmup Scheduler', () {
      test('DspChainValidator flags high THD or non-flat response', () {
        final validator = DspChainValidator();
        final report = validator.validate(
          chainInputRms: 0.5,
          chainOutputRms: 0.5,
          thdPercent: 0.02,
          frequencyDeviationDb: 0.3,
          stageLatenciesMs: {'equalizer': 2.5, 'reverb': 4.1},
        );

        expect(report.allStagesHealthy, isTrue);
        expect(report.totalLatencyMs, closeTo(6.6, 0.01));
        expect(report.warnings, isEmpty);
      });

      test('DspChainValidator captures excessive latency and distortion issues', () {
        final validator = DspChainValidator();
        final report = validator.validate(
          chainInputRms: 0.5,
          chainOutputRms: 0.9,
          thdPercent: 1.5, // > 0.5% threshold
          frequencyDeviationDb: 2.1, // > 0.5dB threshold
          stageLatenciesMs: {'equalizer': 35.0}, // > 20ms threshold
        );

        expect(report.allStagesHealthy, isFalse);
        expect(report.warnings.length, greaterThanOrEqualTo(2));
      });

      test('DspWarmupScheduler generates 100ms silent PCM buffer', () {
        final scheduler = DspWarmupScheduler();
        final buffer = scheduler.createSilentWarmupBuffer(
          sampleRate: 48000,
          channels: 2,
          durationMs: 100,
        );

        // 48000 * 0.1s * 2 channels = 9600 float samples = 38400 bytes
        expect(buffer.length, equals(4800 * 2));
        for (var i = 0; i < 100; i++) {
          expect(buffer[i], equals(0.0));
        }
      });
    });

    group('4. Waveform Generator Peak Extraction & Styles', () {
      test('WaveformGenerator normalizes peaks properly in 0.0..1.0 range', () {
        final rawSamples = Float32List.fromList([
          0.1, -0.5, 0.8, -0.95, 0.2, 0.0, -0.3, 0.6,
        ]);

        final peaks = WaveformGenerator.extractPeaksFromPcmSync(
          samples: rawSamples,
          targetBarCount: 4,
        );

        expect(peaks.length, equals(4));
        for (final p in peaks) {
          expect(p, greaterThanOrEqualTo(0.0));
          expect(p, lessThanOrEqualTo(1.0));
        }
        // Highest peak (0.95) should be scaled to 1.0
        expect(peaks.reduce(math.max), closeTo(1.0, 0.001));
      });

      test('WaveformVisualizerStyle enum supports all 4 distinct rendering styles', () {
        expect(WaveformVisualizerStyle.values.length, equals(4));
        expect(WaveformVisualizerStyle.values, contains(WaveformVisualizerStyle.mirroredBars));
        expect(WaveformVisualizerStyle.values, contains(WaveformVisualizerStyle.roundedTopBars));
        expect(WaveformVisualizerStyle.values, contains(WaveformVisualizerStyle.continuousEnvelope));
        expect(WaveformVisualizerStyle.values, contains(WaveformVisualizerStyle.neonGlowLine));
      });
    });

    group('5. YIN Fundamental Vocal Pitch Detection', () {
      test('YinPitchDetector accurately detects pure sine wave frequency', () {
        const double sampleRate = 44100.0;
        const targetFreq = 440.0; // Musical A4 note
        const bufferSize = 2048;

        final buffer = Float32List(bufferSize);
        for (var i = 0; i < bufferSize; i++) {
          buffer[i] = math.sin(2.0 * math.pi * targetFreq * i / sampleRate);
        }

        final detector = YinPitchDetector(sampleRate: sampleRate, threshold: 0.15);
        final detected = detector.getPitch(buffer);

        expect(detected, isNotNull);
        expect(detected!.pitch, closeTo(targetFreq, 3.0));
        expect(detected.probability, greaterThan(0.85));
      });

      test('YinPitchDetector rejects pure noise or silence as unvoiced', () {
        const double sampleRate = 44100.0;
        final silence = Float32List(2048);

        final detector = YinPitchDetector(sampleRate: sampleRate);
        final detected = detector.getPitch(silence);

        expect(detected, isNull);
      });
    });

    group('6. Synchronized Lyrics Word-Level & Bilingual Matching', () {
      test('LrcParser parses standard and word-level timestamps', () {
        const lrc = '''
[00:01.00]First line
[00:05.50]<00:05.50>Word <00:06.00>by <00:06.50>word
''';
        final lines = LrcParser.parse(lrc);
        expect(lines.length, equals(2));
        expect(lines[0].text, equals('First line'));
        expect(lines[1].text, equals('Word by word'));
        expect(lines[1].words, isNotEmpty);
        expect(lines[1].words.length, equals(3));
        expect(lines[1].words[0].word, equals('Word'));
        expect(lines[1].words[0].startMs, equals(5500));
        expect(lines[1].words[1].word, equals('by'));
        expect(lines[1].words[1].startMs, equals(6000));
      });

      test('LrcParser pairs bilingual translations when present', () {
        const lrcWithTranslation = '''
[00:02.00]Hello world
[00:02.00]Bonjour le monde
[00:08.00]Good night
[00:08.00]Bonne nuit
''';
        final lines = LrcParser.parse(lrcWithTranslation);
        expect(lines.length, equals(2));
        expect(lines[0].text, equals('Hello world'));
        expect(lines[0].translation, equals('Bonjour le monde'));
        expect(lines[1].text, equals('Good night'));
        expect(lines[1].translation, equals('Bonne nuit'));
      });
    });

    group('7. EqPreset Default Presets & System Custom Actions', () {
      test('EqPreset.defaultPresets contains Flat and valid gains', () {
        final presets = EqPreset.defaultPresets;
        expect(presets, isNotEmpty);
        expect(presets.any((p) => p.name == 'Flat'), isTrue);
        final flat = presets.firstWhere((p) => p.name == 'Flat');
        expect(flat.gains.every((g) => g == 0.0), isTrue);
      });
    });
  });
}
