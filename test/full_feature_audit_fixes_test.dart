// test/full_feature_audit_fixes_test.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/services/ytm_url_cache.dart';
import 'package:pulsr/core/utils/lrc_parser.dart';
import 'package:pulsr/data/audio/crossfade_manager.dart';
import 'package:pulsr/data/repositories/music_repository.dart';
import 'package:pulsr/domain/models/download_settings.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/repositories/download_repository_interface.dart';
import 'package:pulsr/domain/usecases/backup_usecases.dart';
import 'package:pulsr/domain/usecases/delete_download.dart';
import 'package:pulsr/domain/usecases/get_download_storage_stats.dart';
import 'package:pulsr/domain/usecases/observe_downloads.dart';
import 'package:pulsr/domain/usecases/pause_download.dart';
import 'package:pulsr/domain/usecases/queue_download.dart';
import 'package:pulsr/domain/usecases/resume_download.dart';
import 'package:pulsr/domain/usecases/retry_download.dart';
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';
import 'package:pulsr/features/widgets/widget_service.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}
class MockDownloadRepository extends Mock implements IDownloadRepository {}
class MockObserveDownloadsUseCase extends Mock implements ObserveDownloadsUseCase {}
class MockGetDownloadStorageStatsUseCase extends Mock implements GetDownloadStorageStatsUseCase {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Pulsr Full Feature Audit Fixes Verification Suite', () {
    // 1. DownloadTask.copyWith with clearError: true sets error to null
    test('1. DownloadTask.copyWith with clearError: true sets error to null', () {
      final task = DownloadTask(
        id: 'task_1',
        videoId: 'vid_1',
        title: 'Title',
        artist: 'Artist',
        createdAt: DateTime(2026, 1, 1),
        error: 'Network Timeout',
      );

      expect(task.error, equals('Network Timeout'));

      final updatedTask = task.copyWith(clearError: true);
      expect(updatedTask.error, isNull);

      // Verify regular copyWith preserves error when clearError is false
      final preservedTask = task.copyWith(title: 'New Title');
      expect(preservedTask.error, equals('Network Timeout'));
      expect(preservedTask.title, equals('New Title'));
    });

    // 2. DownloadSettings.load() returns defaults when prefs corrupted
    test('2. DownloadSettings.load() returns defaults when prefs corrupted', () async {
      // Intentionally store incompatible type so prefs.getBool throws TypeError
      SharedPreferences.setMockInitialValues({
        'setting_wifi_only_mode': 'not_a_boolean',
      });

      final settings = await DownloadSettings.load();
      expect(settings.wifiOnly, isFalse);
      expect(settings.quality, equals('high'));
      expect(settings.maxConcurrent, equals(3));
      expect(settings.downloadLocation, isNull);
    });

    // 3. YtmService per-video circuit breaker: 3 failures on videoA trips for videoA, but videoB is not blocked
    test('3. YtmService per-video circuit breaker: 3 failures on videoA trips for videoA, but videoB is not blocked', () {
      final ytmService = YtmService();

      expect(ytmService.isVideoCoolingDown('videoA'), isFalse);
      expect(ytmService.isVideoCoolingDown('videoB'), isFalse);

      // Record 2 failures for videoA: should not trip yet
      ytmService.recordFailure('videoA');
      ytmService.recordFailure('videoA');
      expect(ytmService.isVideoCoolingDown('videoA'), isFalse);

      // 3rd failure on videoA: trips breaker for videoA
      ytmService.recordFailure('videoA');
      expect(ytmService.isVideoCoolingDown('videoA'), isTrue);

      // videoB must remain unblocked
      expect(ytmService.isVideoCoolingDown('videoB'), isFalse);
    });

    // 4. YtmUrlCache.parseUrlExpiryStamp handles seconds and milliseconds epochs correctly
    test('4. YtmUrlCache.parseUrlExpiryStamp handles seconds and milliseconds epochs correctly', () {
      // Query param with seconds (< 1e11)
      const secUrl = 'https://rr1---sn.googlevideo.com/videoplayback?expire=1712345678&id=xyz';
      final secDate = YtmUrlCache.parseUrlExpiryStamp(secUrl);
      expect(secDate, isNotNull);
      expect(secDate, equals(DateTime.fromMillisecondsSinceEpoch(1712345678 * 1000)));

      // Query param with milliseconds (>= 1e11)
      const msUrl = 'https://rr1---sn.googlevideo.com/videoplayback?expire=1712345678000&id=xyz';
      final msDate = YtmUrlCache.parseUrlExpiryStamp(msUrl);
      expect(msDate, isNotNull);
      expect(msDate, equals(DateTime.fromMillisecondsSinceEpoch(1712345678000)));

      // Path format with seconds
      const pathUrl = 'https://rr1---sn.googlevideo.com/videoplayback/expire/1712345678/id/xyz';
      final pathDate = YtmUrlCache.parseUrlExpiryStamp(pathUrl);
      expect(pathDate, isNotNull);
      expect(pathDate, equals(DateTime.fromMillisecondsSinceEpoch(1712345678 * 1000)));

      // Invalid / missing
      const invalidUrl = 'https://rr1---sn.googlevideo.com/videoplayback?id=xyz';
      expect(YtmUrlCache.parseUrlExpiryStamp(invalidUrl), isNull);
    });

    // 5. MusicRepository.toFtsQuery sanitizes *, ", ^, -
    test('5. MusicRepository.toFtsQuery sanitizes *, ", ^, -', () {
      final result = MusicRepository.toFtsQuery('hello* "world" -test ^query');
      expect(result, isNotNull);
      // Special characters must be stripped, words enclosed in quotes with * suffix
      expect(result, equals('"hello"* "world"* "test"* "query"*'));

      // Check empty or only special chars returns null
      expect(MusicRepository.toFtsQuery('*** --- """ ^^^'), isNull);
    });

    // 6. ImportBackupUseCase.validateSchema throws FormatException with unsupported version message for version: 5
    test('6. ImportBackupUseCase.validateSchema throws FormatException with unsupported version message for version: 5', () {
      expect(
        () => ImportBackupUseCase.validateSchema({'version': 5}),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          equals('Unsupported backup version: 5. Please update Pulsr.'),
        )),
      );

      // Valid versions (1..4) do not throw version error
      expect(() => ImportBackupUseCase.validateSchema({'version': 1}), returnsNormally);
      expect(() => ImportBackupUseCase.validateSchema({'version': 2}), returnsNormally);
      expect(() => ImportBackupUseCase.validateSchema({'version': 3}), returnsNormally);
      expect(() => ImportBackupUseCase.validateSchema({'version': 4}), returnsNormally);
    });

    // 7. LrcParser.parse skips malformed timestamp lines without throwing
    test('7. LrcParser.parse skips malformed timestamp lines without throwing', () {
      const lrcContent = '''
[ar:Artist]
[ti:Title]
[9999999999999999999999999999999:00.00] Overflow timestamp line
[invalid:time] Corrupted timestamp line
[01:23.45] Valid Line 1
[02:34.56] Valid Line 2
''';

      final lines = LrcParser.parse(lrcContent);
      expect(lines.length, equals(2));
      expect(lines[0].text, equals('Valid Line 1'));
      expect(lines[0].timestamp, equals(const Duration(minutes: 1, seconds: 23, milliseconds: 450)));
      expect(lines[1].text, equals('Valid Line 2'));
      expect(lines[1].timestamp, equals(const Duration(minutes: 2, seconds: 34, milliseconds: 560)));
    });

    // 8. CrossfadeManager.cancel() completes _crossfadeCompleter safely without throwing
    test('8. CrossfadeManager.cancel() completes _crossfadeCompleter safely without throwing', () async {
      final crossfadeManager = CrossfadeManager();
      final playerA = MockAudioPlayer();
      final playerB = MockAudioPlayer();

      when(() => playerA.setVolume(any())).thenAnswer((_) async {});
      when(() => playerB.setVolume(any())).thenAnswer((_) async {});
      when(() => playerA.stop()).thenAnswer((_) async {});
      when(() => playerB.stop()).thenAnswer((_) async {});
      when(() => playerA.dspSetGainCurve(any(), segmentMs: any(named: 'segmentMs'))).thenAnswer((_) async => false);
      when(() => playerB.dspSetGainCurve(any(), segmentMs: any(named: 'segmentMs'))).thenAnswer((_) async => false);
      when(() => playerA.dspClearGainCurve()).thenAnswer((_) async => false);
      when(() => playerB.dspClearGainCurve()).thenAnswer((_) async => false);

      crossfadeManager.beginCrossfade(1);
      expect(crossfadeManager.isCrossfading, isTrue);

      // Cancel must complete active crossfade without throwing
      await expectLater(crossfadeManager.cancel(playerA, playerB), completes);
      expect(crossfadeManager.isCrossfading, isFalse);

      // Awaiting waitForActiveCrossfade must also complete immediately
      await expectLater(crossfadeManager.waitForActiveCrossfade(), completes);

      // Second cancel invocation must also be safe
      await expectLater(crossfadeManager.cancel(playerA, playerB), completes);

      crossfadeManager.dispose();
    });

    // 9. DownloadsCubit.cancelDownload pauses and deletes task
    test('9. DownloadsCubit.cancelDownload pauses and deletes task', () async {
      final mockRepo = MockDownloadRepository();
      when(() => mockRepo.reconcileOnBoot()).thenAnswer((_) async {});
      when(() => mockRepo.getAllDownloads()).thenAnswer((_) async => []);
      when(() => mockRepo.observeDownloads()).thenAnswer((_) => const Stream.empty());
      when(() => mockRepo.pauseDownload('vid_abc')).thenAnswer((_) async => const Right(unit));
      when(() => mockRepo.deleteDownload('vid_abc')).thenAnswer((_) async => const Right(unit));
      when(() => mockRepo.getStorageStats()).thenAnswer((_) async => const Right(StorageStats(
            totalBytes: 1000,
            freeBytes: 500,
            usedBytes: 100,
            downloadedSongsCount: 1,
          )));

      final queueUseCase = QueueDownloadUseCase(mockRepo);
      final pauseUseCase = PauseDownloadUseCase(mockRepo);
      final resumeUseCase = ResumeDownloadUseCase(mockRepo);
      final retryUseCase = RetryDownloadUseCase(mockRepo);
      final deleteUseCase = DeleteDownloadUseCase(mockRepo);
      final observeUseCase = ObserveDownloadsUseCase(mockRepo);
      final storageStatsUseCase = GetDownloadStorageStatsUseCase(mockRepo);

      final cubit = DownloadsCubit(
        queueUseCase,
        pauseUseCase,
        resumeUseCase,
        retryUseCase,
        deleteUseCase,
        observeUseCase,
        storageStatsUseCase,
        mockRepo,
      );

      await cubit.cancelDownload('vid_abc');

      verify(() => mockRepo.pauseDownload('vid_abc')).called(1);
      verify(() => mockRepo.deleteDownload('vid_abc')).called(1);

      await cubit.close();
    });

    // 10. WidgetService._pruneOldWidgetArtwork prunes oldest files first
    test('10. WidgetService._pruneOldWidgetArtwork prunes oldest files first', () async {
      final tempDir = Directory.systemTemp.createTempSync('widget_prune_test_');

      try {
        final widgetService = WidgetService();
        final now = DateTime.now();

        // Create 52 artwork files (cache limit is 50, so 2 oldest should be pruned)
        final createdFiles = <File>[];
        for (int i = 0; i < 52; i++) {
          final file = File('${tempDir.path}${Platform.pathSeparator}pulsr_widget_art_$i.png');
          file.writeAsBytesSync([0, 1, 2]);
          // Set modified timestamp: file 0 is 52 hours ago, file 51 is 1 hour ago
          file.setLastModifiedSync(now.subtract(Duration(hours: 52 - i)));
          createdFiles.add(file);
        }

        expect(createdFiles.every((f) => f.existsSync()), isTrue);

        await widgetService.pruneOldWidgetArtwork(tempDir);

        // Files 0 and 1 (oldest) should be deleted
        expect(createdFiles[0].existsSync(), isFalse);
        expect(createdFiles[1].existsSync(), isFalse);

        // Files 2 to 51 (the 50 newest) should remain
        for (int i = 2; i < 52; i++) {
          expect(createdFiles[i].existsSync(), isTrue);
        }
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });
  });
}
