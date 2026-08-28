// test/features/downloads/cubit/downloads_chaos_test.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/usecases/delete_download.dart';
import 'package:pulsr/domain/usecases/get_download_storage_stats.dart';
import 'package:pulsr/domain/usecases/observe_downloads.dart';
import 'package:pulsr/domain/usecases/pause_download.dart';
import 'package:pulsr/domain/usecases/prioritize_download.dart';
import 'package:pulsr/domain/usecases/queue_download.dart';
import 'package:pulsr/domain/usecases/resume_download.dart';
import 'package:pulsr/domain/usecases/retry_download.dart';
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';

class MockQueueDownloadUseCase extends Mock implements QueueDownloadUseCase {}
class MockPauseDownloadUseCase extends Mock implements PauseDownloadUseCase {}
class MockResumeDownloadUseCase extends Mock implements ResumeDownloadUseCase {}
class MockRetryDownloadUseCase extends Mock implements RetryDownloadUseCase {}
class MockDeleteDownloadUseCase extends Mock implements DeleteDownloadUseCase {}
class MockPrioritizeDownloadUseCase extends Mock implements PrioritizeDownloadUseCase {}
class MockObserveDownloadsUseCase extends Mock implements ObserveDownloadsUseCase {}
class MockGetDownloadStorageStatsUseCase extends Mock implements GetDownloadStorageStatsUseCase {}

void main() {
  setUpAll(() {
    registerFallbackValue(DownloadTask(
      id: 'fallback',
      videoId: 'fallback',
      title: 'Fallback',
      artist: 'Fallback',
      createdAt: DateTime.now(),
    ));
  });

  group('Downloads Chaos v2 & Concurrency Suite', () {
    test('1000 seeded runs with prune-race assert zero overlapping executions and zero leaks', () async {
      const baseSeed = 1337;
      final mockQueue = MockQueueDownloadUseCase();
      final mockPause = MockPauseDownloadUseCase();
      final mockResume = MockResumeDownloadUseCase();
      final mockRetry = MockRetryDownloadUseCase();
      final mockDelete = MockDeleteDownloadUseCase();
      final mockPrioritize = MockPrioritizeDownloadUseCase();
      final mockObserve = MockObserveDownloadsUseCase();
      final mockStorageStats = MockGetDownloadStorageStatsUseCase();
      final streamCtrl = StreamController<DownloadTask>.broadcast();

      // Concurrency tracking: if activeCount > 1 for same ID, a race violation occurred
      final activeExecuting = <String, int>{};
      int maxConcurrencyObserved = 0;

      Future<void> executeTracked(String id, Future<void> Function() work) async {
        final current = (activeExecuting[id] ?? 0) + 1;
        activeExecuting[id] = current;
        if (current > maxConcurrencyObserved) {
          maxConcurrencyObserved = current;
        }
        expect(current, lessThanOrEqualTo(1), reason: 'Concurrent execution detected for task $id');
        try {
          await work();
        } finally {
          activeExecuting[id] = (activeExecuting[id] ?? 1) - 1;
        }
      }

      when(() => mockObserve.call()).thenAnswer((_) => streamCtrl.stream);
      when(() => mockObserve.getAll()).thenAnswer((_) async => []);
      when(() => mockStorageStats.call()).thenAnswer((_) async => const Right(StorageStats()));

      when(() => mockQueue.call(any())).thenAnswer((inv) async {
        final task = inv.positionalArguments[0] as DownloadTask;
        await executeTracked(task.videoId, () async => await Future.delayed(const Duration(microseconds: 50)));
        return const Right('ok');
      });

      when(() => mockPause.call(any())).thenAnswer((inv) async {
        final id = inv.positionalArguments[0] as String;
        await executeTracked(id, () async => await Future.delayed(const Duration(microseconds: 50)));
        return const Right(unit);
      });

      when(() => mockResume.call(any())).thenAnswer((inv) async {
        final id = inv.positionalArguments[0] as String;
        await executeTracked(id, () async => await Future.delayed(const Duration(microseconds: 50)));
        return const Right(unit);
      });

      when(() => mockRetry.call(any())).thenAnswer((inv) async {
        final id = inv.positionalArguments[0] as String;
        await executeTracked(id, () async => await Future.delayed(const Duration(microseconds: 50)));
        return const Right(unit);
      });

      when(() => mockDelete.call(any())).thenAnswer((inv) async {
        final id = inv.positionalArguments[0] as String;
        await executeTracked(id, () async => await Future.delayed(const Duration(microseconds: 50)));
        return const Right(unit);
      });

      when(() => mockPrioritize.call(any())).thenAnswer((inv) async {
        final id = inv.positionalArguments[0] as String;
        await executeTracked(id, () async => await Future.delayed(const Duration(microseconds: 50)));
        return const Right(unit);
      });

      final cubit = DownloadsCubit(
        mockQueue,
        mockPause,
        mockResume,
        mockRetry,
        mockDelete,
        mockObserve,
        mockStorageStats,
        null,
        mockPrioritize,
      );

      final videoIds = List.generate(8, (i) => 'chaos_vid_$i');

      // 1000 SEEDED RUNS
      for (int run = 0; run < 1000; run++) {
        final runSeed = baseSeed + run;
        final rng = Random(runSeed);
        final runFutures = <Future<void>>[];

        try {
          // Specific prune-race scenario: delete(vid) immediately followed by queue(vid) & prioritize(vid)
          if (run % 10 == 0) {
            final targetVid = videoIds[rng.nextInt(videoIds.length)];
            runFutures.add(cubit.deleteDownload(targetVid));
            runFutures.add(cubit.queueDownload(DownloadTask(
              id: 'task_$targetVid',
              videoId: targetVid,
              title: 'Prune Race Task',
              artist: 'Artist',
              createdAt: DateTime.now(),
            )));
            runFutures.add(cubit.prioritizeDownload(targetVid));
          } else {
            // General randomized operations sequence
            final vid = videoIds[rng.nextInt(videoIds.length)];
            final op = rng.nextInt(6);
            switch (op) {
              case 0:
                runFutures.add(cubit.queueDownload(DownloadTask(
                  id: 'task_$vid',
                  videoId: vid,
                  title: 'Song $vid',
                  artist: 'Artist',
                  createdAt: DateTime.now(),
                )));
                break;
              case 1:
                runFutures.add(cubit.pauseDownload(vid));
                break;
              case 2:
                runFutures.add(cubit.resumeDownload(vid));
                break;
              case 3:
                runFutures.add(cubit.retryDownload(vid));
                break;
              case 4:
                runFutures.add(cubit.deleteDownload(vid));
                break;
              case 5:
                runFutures.add(cubit.prioritizeDownload(vid));
                break;
            }
          }

          await Future.wait(runFutures);

          // Invariant checks per run
          expect(cubit.state.activeCount, greaterThanOrEqualTo(0), reason: 'Failed activeCount on seed $runSeed');
          expect(cubit.state.pausedCount, greaterThanOrEqualTo(0), reason: 'Failed pausedCount on seed $runSeed');
          expect(cubit.state.completedCount, greaterThanOrEqualTo(0), reason: 'Failed completedCount on seed $runSeed');
          expect(cubit.state.taskList.length, equals(cubit.state.tasks.length), reason: 'Failed list conservation on seed $runSeed');
        } catch (e) {
          fail('Chaos run failed on seed $runSeed: $e');
        }
      }

      expect(maxConcurrencyObserved, lessThanOrEqualTo(1), reason: 'Zero overlapping operations guaranteed across all 1000 runs');

      // Close and verify clean disposal
      await cubit.close();
      expect(cubit.activeSubscriptionCount, equals(0));
      await streamCtrl.close();
    });
  });
}
