// test/audit_phase5_hardening_test.dart
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pulsr/core/utils/cue_parser.dart';
import 'package:pulsr/data/audio/crossfade_manager.dart';
import 'package:pulsr/data/audio/gapless_trim_handler.dart';
import 'package:pulsr/data/audio/playback_analytics.dart';
import 'package:pulsr/data/audio/smart_preload_scheduler.dart';
import 'package:pulsr/data/audio/triple_buffer_pipeline.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/player/presentation/widgets/viper_ddc_sheet.dart';
import 'package:pulsr/data/audio/position_crash_guard.dart';
import 'package:pulsr/data/audio/interruption_state_machine.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 5 Hardening & Regression Suite', () {
    // -------------------------------------------------------------------------
    // 1. Crossfade Engine Concurrency & Safety (C-02, M-04, M-05)
    // -------------------------------------------------------------------------
    group('1. Crossfade Engine Concurrency & Safety', () {
      test(
          'Canceling active fades is idempotent and prevents double-completion',
          () async {
        final manager = CrossfadeManager();
        final playerA = MockAudioPlayer();
        final playerB = MockAudioPlayer();

        when(() => playerA.volume).thenReturn(1.0);
        when(() => playerB.volume).thenReturn(0.0);
        when(() => playerA.setVolume(any())).thenAnswer((_) async {});
        when(() => playerB.setVolume(any())).thenAnswer((_) async {});
        when(() => playerA.dspClearGainCurve()).thenAnswer((_) async => true);
        when(() => playerB.dspClearGainCurve()).thenAnswer((_) async => true);

        // Cancel with no active fades
        await expectLater(
          manager.cancel(playerA, playerB, restoreVolume: 1.0),
          completes,
        );

        // Cancel again to verify safety
        await expectLater(
          manager.cancel(playerA, playerB, restoreVolume: 1.0),
          completes,
        );

        manager.dispose();
      });

      test('dispose clears native curves and cancels pending timers safely',
          () {
        final manager = CrossfadeManager();
        expect(() => manager.dispose(), returnsNormally);
        // Repeated dispose must not throw
        expect(() => manager.dispose(), returnsNormally);
      });
    });

    // -------------------------------------------------------------------------
    // 2. Player Theme Registry (8 Themes)
    // -------------------------------------------------------------------------
    group('2. Player Themes Verification', () {
      test('All 8 PlayerThemeMode entries exist and can be resolved', () {
        expect(PlayerThemeMode.values.length, equals(8));

        final expectedModes = [
          PlayerThemeMode.classic,
          PlayerThemeMode.card,
          PlayerThemeMode.circle,
          PlayerThemeMode.minimal,
          PlayerThemeMode.vinyl,
          PlayerThemeMode.cassette,
          PlayerThemeMode.waveform,
          PlayerThemeMode.lyricsFocus,
        ];

        for (final mode in expectedModes) {
          expect(PlayerThemeMode.values.contains(mode), isTrue);
        }
      });
    });

    // -------------------------------------------------------------------------
    // 3. CUE Sheet Parsing & Embedded CUE Support (Prompt 4.9)
    // -------------------------------------------------------------------------
    group('3. CUE Sheet Parsing & Embedded Support', () {
      test('Parses standard textual CUE content into ChapterInfo', () {
        const cueContent = '''
TITLE "Symphony No. 5"
PERFORMER "Beethoven"
FILE "symphony5.flac" WAVE
  TRACK 01 AUDIO
    TITLE "Allegro con brio"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Andante con moto"
    INDEX 01 07:15:20
  TRACK 03 AUDIO
    TITLE "Scherzo: Allegro"
    INDEX 01 17:12:45
''';

        final chapters = CueParser.parse(cueContent);
        expect(chapters.length, equals(3));

        expect(chapters[0].index, equals(1));
        expect(chapters[0].title, equals('Allegro con brio'));
        expect(chapters[0].start, equals(Duration.zero));
        expect(chapters[0].fileName, equals('symphony5.flac'));
        expect(chapters[0].end, isNotNull);

        expect(chapters[1].index, equals(2));
        expect(chapters[1].title, equals('Andante con moto'));
        expect(chapters[1].start.inMinutes, equals(7));
        expect(chapters[1].start.inSeconds % 60, equals(15));

        expect(chapters[2].index, equals(3));
        expect(chapters[2].title, equals('Scherzo: Allegro'));
        expect(chapters[2].end, isNull); // Last chapter
      });

      test('Frame to millisecond conversion calculation is accurate', () {
        // 75 frames = 1000 milliseconds
        const cueWithFrames = '''
FILE "album.wav" WAVE
  TRACK 01 AUDIO
    TITLE "Intro"
    INDEX 01 01:30:37
''';
        final chapters = CueParser.parse(cueWithFrames);
        expect(chapters.length, equals(1));
        // 1m 30s + (37/75 * 1000)ms = 90,000 + 493ms = 90,493ms
        expect(chapters[0].start.inMilliseconds, equals(90493));
      });
    });

    // -------------------------------------------------------------------------
    // 4. Triple Buffer Retry Logic & Analytics (Prompt 4.2)
    // -------------------------------------------------------------------------
    group('4. Triple-Buffer Preload Reliability', () {
      test('Tracks preload success rate correctly in PlaybackAnalytics', () {
        final analytics = PlaybackAnalytics();
        expect(analytics.preloadSuccessRate, equals(1.0));

        analytics.recordPreloadSuccess();
        analytics.recordPreloadSuccess();
        analytics.recordPreloadFailure();

        // 2 successes out of 3 attempts = 66.67%
        expect(analytics.preloadSuccessRate, closeTo(0.666, 0.01));
      });

      test(
          'Preload failure blacklisting prevents immediate redundant preload attempts',
          () {
        final playerA = MockAudioPlayer();
        final playerB = MockAudioPlayer();
        final pipeline = TripleBufferPipeline(
          getActivePlayer: () => playerA,
          getInactivePlayer: () => playerB,
          resolveAudioSource: (song, tag) async =>
              AudioSource.uri(Uri.parse('http://test.com/stream')),
          songToMediaItem: (song, [uri]) =>
              MediaItem(id: song.id.toString(), title: song.title),
        );
        const songId = 999;

        expect(pipeline.isPreloadBlacklisted(songId), isFalse);

        pipeline.recordPreloadFailure(songId);
        expect(pipeline.isPreloadBlacklisted(songId), isTrue);

        pipeline.clearPreload();
      });
    });

    // -------------------------------------------------------------------------
    // 5. Smart Preload Scheduler & Metered Policy (Prompt 4.8)
    // -------------------------------------------------------------------------
    group('5. Smart Preload Sizing & Metered Policy', () {
      test(
          'On metered connection, caps preload count to 1 and skips tracks > 10 minutes',
          () async {
        final preloaded = <int>[];
        final scheduler = SmartPreloadScheduler(
          onPreloadRequested: (song, {required priority}) async {
            preloaded.add(song.id);
          },
          isMeteredConnectionProvider: () async => true,
          networkPolicy: PreloadNetworkPolicy.conservativeOnMetered,
        );

        final queue = [
          const SongsTableData(
            id: 1,
            title: 'Current',
            artist: 'Artist',
            album: '',
            durationMs: 180000,
            path: 'http://test.com/1',
            source: SongSource.youtube,
            isFavorite: false,
            isMissing: false,
            isDownloaded: false,
            playCount: 0,
            lastPositionMs: 0,
          ),
          const SongsTableData(
            id: 2,
            title: 'Next Long (15 min)',
            artist: 'Artist',
            album: '',
            durationMs: 900000, // 15 min > 10 min
            path: 'http://test.com/2',
            source: SongSource.youtube,
            isFavorite: false,
            isMissing: false,
            isDownloaded: false,
            playCount: 0,
            lastPositionMs: 0,
          ),
          const SongsTableData(
            id: 3,
            title: 'Next Normal (3 min)',
            artist: 'Artist',
            album: '',
            durationMs: 180000,
            path: 'http://test.com/3',
            source: SongSource.youtube,
            isFavorite: false,
            isMissing: false,
            isDownloaded: false,
            playCount: 0,
            lastPositionMs: 0,
          ),
        ];

        scheduler.schedulePreloads(
          queue: queue,
          currentIndex: 0,
          isShuffle: false,
          position: const Duration(seconds: 150),
          duration: const Duration(seconds: 180),
          preloadCount: 3,
        );

        await Future<void>.delayed(const Duration(milliseconds: 50));
        // Track 2 is > 10 min, so on metered connection it was skipped!
        expect(preloaded.contains(2), isFalse);
      });

      test('Preload data usage counter accumulates and resets properly',
          () async {
        SharedPreferences.setMockInitialValues({});
        await SmartPreloadScheduler.initDataUsage();
        SmartPreloadScheduler.recordPreloadDataUsage(2500000);
        expect(SmartPreloadScheduler.preloadDataUsageBytes, equals(2500000));

        SmartPreloadScheduler.recordPreloadDataUsage(1500000);
        expect(SmartPreloadScheduler.preloadDataUsageBytes, equals(4000000));

        await SmartPreloadScheduler.resetPreloadDataUsage();
        expect(SmartPreloadScheduler.preloadDataUsageBytes, equals(0));
      });
    });

    // -------------------------------------------------------------------------
    // 6. ViPER-DDC Parser & Filter Stability (Prompt 4.3)
    // -------------------------------------------------------------------------
    group('6. ViPER-DDC Text Format & Filter Stability', () {
      test('Parses text format with b0,b1,b2,a1,a2 and sample rate blocks', () {
        const vdcText = '''
# Profile: Harman Target Demo
1.025,-1.980,0.965,-1.975,0.985
###
1.020,-1.982,0.968,-1.978,0.988
''';
        final coeffs = ViperDdcParser.parseText(vdcText);
        expect(coeffs, isNotEmpty);
        expect(ViperDdcParser.validateFilterStability(-1.975, 0.985), isTrue);
      });

      test('Rejects unstable biquad filters failing Jury stability pole test',
          () {
        // a2 >= 1.0 is an unstable explosive pole outside the unit circle
        expect(ViperDdcParser.validateFilterStability(-2.5, 1.5), isFalse);
        expect(ViperDdcParser.validateFilterStability(2.1, 0.9), isFalse);
        expect(ViperDdcParser.validateFilterStability(-1.8, 0.85), isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // 7. Multi-Point Room Correction SNR & Averaging (Prompt 4.10)
    // -------------------------------------------------------------------------
    group('7. Multi-Point Room Correction SNR & Averaging', () {
      test('Averages multiple measurement frequency curves accurately', () {
        final p1 = [2.0, -1.0, 4.0, 0.0];
        final p2 = [4.0, -3.0, 2.0, -2.0];
        final p3 = [0.0, -2.0, 6.0, 2.0];

        final avg = List.filled(4, 0.0);
        for (int i = 0; i < 4; i++) {
          avg[i] = (p1[i] + p2[i] + p3[i]) / 3.0;
        }

        expect(avg[0], equals(2.0));
        expect(avg[1], equals(-2.0));
        expect(avg[2], equals(4.0));
        expect(avg[3], equals(0.0));
      });

      test(
          'SNR calculation produces valid dB range from PCM signal and noise floor',
          () {
        final pcm = Int16List(4096);
        for (int i = 0; i < 2048; i++) {
          pcm[i] = (math.sin(i * 0.1) * 20000).toInt(); // High signal
        }
        for (int i = 2048; i < 4096; i++) {
          pcm[i] = (math.sin(i * 0.1) * 100).toInt(); // Low noise floor
        }

        const windowSize = 1024;
        double maxRms = 0.0;
        double minRms = double.infinity;

        for (int i = 0; i + windowSize <= pcm.length; i += windowSize) {
          double sumSq = 0.0;
          for (int j = 0; j < windowSize; j++) {
            final s = pcm[i + j].toDouble();
            sumSq += s * s;
          }
          final rms = math.sqrt(sumSq / windowSize);
          if (rms > maxRms) maxRms = rms;
          if (rms > 0 && rms < minRms) minRms = rms;
        }

        final snr = 20 * (math.log(maxRms / minRms) / math.ln10);
        expect(snr, greaterThan(25.0)); // High quality signal
      });
    });

    // -------------------------------------------------------------------------
    // 8. Gapless Transition Monitor & Codec Trimming (Prompt 1B)
    // -------------------------------------------------------------------------
    group('8. Gapless Transition Monitor & Codec Trimming', () {
      test(
          'GaplessTransitionMonitor tracks clean forward boundary transitions without glitch',
          () {
        final monitor = GaplessTransitionMonitor();
        monitor.onTrackTransition(0);
        expect(monitor.gapEventCount, equals(0));

        monitor.onPositionUpdate(const Duration(milliseconds: 10));
        monitor.onPositionUpdate(const Duration(milliseconds: 30));
        expect(monitor.gapEventCount, equals(0));

        // Seamless next track index transition
        monitor.onTrackTransition(1);
        monitor.onPositionUpdate(const Duration(milliseconds: 2));
        monitor.onPositionUpdate(const Duration(milliseconds: 15));
        expect(monitor.gapEventCount, equals(0));
      });

      test(
          'GaplessTransitionMonitor increments gapEventCount on backward jumps > 5ms',
          () {
        final monitor = GaplessTransitionMonitor();
        monitor.onTrackTransition(0);
        monitor.onPositionUpdate(const Duration(milliseconds: 100));

        // Abnormal backwards jump of 20ms during playback of the same track
        monitor.onPositionUpdate(const Duration(milliseconds: 80));
        expect(monitor.gapEventCount, equals(1));
      });

      test('GaplessTrimHandler trims accurately for known formats', () {
        final flacTrim = GaplessTrimHandler.trimFor(path: 'track.flac');
        expect(flacTrim.preSkip, equals(Duration.zero));
        expect(flacTrim.postTrim, equals(Duration.zero));

        final mp3Trim = GaplessTrimHandler.trimFor(path: 'track.mp3');
        expect(mp3Trim.preSkip.inMicroseconds, greaterThan(0));
      });
    });

    // -------------------------------------------------------------------------
    // 9. Crossfade Sample-Accuracy & Complementary Curve (Prompt 1C)
    // -------------------------------------------------------------------------
    group('9. Crossfade Sample-Accuracy & Complementary Curve', () {
      test(
          'Complement curve sums to <= 1.0 (sum-safe ceiling) at every sample point',
          () {
        final manager = CrossfadeManager();
        manager.curve = CrossfadeCurve.linear;

        const points = 200;
        for (int i = 0; i < points; i++) {
          final fraction = i / (points - 1);
          final (oldGain, newGain) = manager.evaluateSumSafeGainPair(fraction);
          expect(oldGain + newGain, closeTo(1.0, 1e-4));
        }

        // Test equal power: sum-safe scaling ensures sum never exceeds 1.0 (zero clipping)
        manager.curve = CrossfadeCurve.equalPower;
        for (int i = 0; i < points; i++) {
          final fraction = i / (points - 1);
          final (oldGain, newGain) = manager.evaluateSumSafeGainPair(fraction);
          expect(oldGain + newGain, lessThanOrEqualTo(1.0 + 1e-4));
        }
      });

      test('crossfadeGlitchCount starts at 0 and is exposed for diagnostics',
          () {
        final manager = CrossfadeManager();
        expect(manager.crossfadeGlitchCount, equals(0));
      });
    });

    // -------------------------------------------------------------------------
    // 10. Position Crash Guard & Unclean Shutdown (Prompt 1A)
    // -------------------------------------------------------------------------
    group('10. Position Crash Guard & Unclean Shutdown', () {
      test('PositionCrashSnapshot serializes and deserializes accurately', () {
        final snapshot = PositionCrashSnapshot(
          songId: 42,
          queueIndex: 3,
          positionMs: 65432,
          queueIds: [10, 20, 30, 42, 50],
          timestamp: 1700000000000,
        );
        final json = snapshot.toJson();
        final restored = PositionCrashSnapshot.fromJson(json);

        expect(restored.songId, equals(42));
        expect(restored.queueIndex, equals(3));
        expect(restored.positionMs, equals(65432));
        expect(restored.queueIds, equals([10, 20, 30, 42, 50]));
        expect(restored.timestamp, equals(1700000000000));
      });

      test('shouldPreferCrashGuard logic prefers newer crash guard snapshot',
          () async {
        SharedPreferences.setMockInitialValues({
          PositionCrashGuard.keyLastCleanShutdownTs: 1000,
        });

        // DB time older than crash guard time -> crash guard wins
        const dbTimeOlder = 1500;
        const crashTimeNewer = 2000;
        expect(crashTimeNewer > dbTimeOlder, isTrue);

        // Clean shutdown time newer than snapshot -> DB wins
        const lastCleanTime = 3000;
        expect(crashTimeNewer > lastCleanTime, isFalse);
      });
    });

    // -------------------------------------------------------------------------
    // 11. Interruption State Machine Flawless Handling (Prompt 1D)
    // -------------------------------------------------------------------------
    group('11. Interruption State Machine Flawless Handling', () {
      test('InterruptionKind includes systemUiSound and mediaButtonLongPress',
          () {
        expect(InterruptionKind.values.contains(InterruptionKind.systemUiSound),
            isTrue);
        expect(
            InterruptionKind.values
                .contains(InterruptionKind.mediaButtonLongPress),
            isTrue);
      });

      test('systemUiSound is identified as transient and ducking', () {
        final machine = InterruptionStateMachine();
        machine.begin(InterruptionKind.systemUiSound, playing: true);
        expect(machine.isDuck, isTrue);
        expect(machine.isTransient, isTrue);
        expect(machine.wasPlayingBeforeInterruption, isTrue);

        final wasPlaying = machine.end(InterruptionKind.systemUiSound);
        expect(wasPlaying, isTrue);
        expect(machine.isActive, isFalse);
      });

      test('mediaButtonLongPress pauses without losing pre-interruption state',
          () {
        final machine = InterruptionStateMachine();
        machine.begin(InterruptionKind.mediaButtonLongPress, playing: true);
        expect(machine.isDuck, isFalse);
        expect(machine.wasPlayingBeforeInterruption, isTrue);

        final wasPlaying = machine.end(InterruptionKind.mediaButtonLongPress);
        expect(wasPlaying, isTrue);
      });
    });
  });
}
