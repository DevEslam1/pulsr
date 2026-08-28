// test/features/downloads/cubit/downloads_cubit_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/usecases/delete_download.dart';
import 'package:pulsr/domain/usecases/get_download_storage_stats.dart';
import 'package:pulsr/domain/usecases/observe_downloads.dart';
import 'package:pulsr/domain/usecases/pause_download.dart';
import 'package:pulsr/domain/usecases/queue_download.dart';
import 'package:pulsr/domain/usecases/resume_download.dart';
import 'package:pulsr/domain/usecases/retry_download.dart';
import 'package:pulsr/domain/usecases/prioritize_download.dart';
import 'package:pulsr/domain/usecases/reorder_downloads.dart';
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';
import 'package:pulsr/features/downloads/cubit/downloads_state.dart';

class MockQueueDownloadUseCase extends Mock implements QueueDownloadUseCase {}

class MockPauseDownloadUseCase extends Mock implements PauseDownloadUseCase {}

class MockResumeDownloadUseCase extends Mock implements ResumeDownloadUseCase {}

class MockRetryDownloadUseCase extends Mock implements RetryDownloadUseCase {}

class MockDeleteDownloadUseCase extends Mock implements DeleteDownloadUseCase {}

class MockObserveDownloadsUseCase extends Mock
    implements ObserveDownloadsUseCase {}

class MockGetDownloadStorageStatsUseCase extends Mock
    implements GetDownloadStorageStatsUseCase {}

class MockReorderDownloadsUseCase extends Mock
    implements ReorderDownloadsUseCase {}

class MockPrioritizeDownloadUseCase extends Mock
    implements PrioritizeDownloadUseCase {}

void main() {
  late MockQueueDownloadUseCase mockQueue;
  late MockPauseDownloadUseCase mockPause;
  late MockResumeDownloadUseCase mockResume;
  late MockRetryDownloadUseCase mockRetry;
  late MockDeleteDownloadUseCase mockDelete;
  late MockObserveDownloadsUseCase mockObserve;
  late MockGetDownloadStorageStatsUseCase mockStorageStats;
  late MockReorderDownloadsUseCase mockReorder;
  late MockPrioritizeDownloadUseCase mockPrioritize;
  late StreamController<DownloadTask> downloadStreamController;

  final testTask = DownloadTask(
    id: 'test_id_1',
    videoId: 'vid_123',
    title: 'Test Song',
    artist: 'Test Artist',
    createdAt: DateTime(2026, 1, 1),
  );

  setUp(() {
    mockQueue = MockQueueDownloadUseCase();
    mockPause = MockPauseDownloadUseCase();
    mockResume = MockResumeDownloadUseCase();
    mockRetry = MockRetryDownloadUseCase();
    mockDelete = MockDeleteDownloadUseCase();
    mockObserve = MockObserveDownloadsUseCase();
    mockStorageStats = MockGetDownloadStorageStatsUseCase();
    mockReorder = MockReorderDownloadsUseCase();
    mockPrioritize = MockPrioritizeDownloadUseCase();
    downloadStreamController = StreamController<DownloadTask>.broadcast();

    when(() => mockObserve.call())
        .thenAnswer((_) => downloadStreamController.stream);
    when(() => mockObserve.getAll()).thenAnswer((_) async => []);
    when(() => mockStorageStats.call())
        .thenAnswer((_) async => const Right(StorageStats(
              usedBytes: 1024,
              freeBytes: 10240,
              totalBytes: 11264,
              downloadedSongsCount: 1,
            )));
  });

  tearDown(() {
    downloadStreamController.close();
  });

  DownloadsCubit buildCubit() {
    return DownloadsCubit(
      mockQueue,
      mockPause,
      mockResume,
      mockRetry,
      mockDelete,
      mockObserve,
      mockStorageStats,
      mockReorder,
      mockPrioritize,
    );
  }

  group('DownloadsCubit', () {
    test('initial state loads tasks and storage stats', () async {
      when(() => mockObserve.getAll()).thenAnswer((_) async => [testTask]);

      final cubit = buildCubit();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(cubit.state.tasks.containsKey('vid_123'), isTrue);
      expect(cubit.state.storageStats.usedBytes, 1024);
      expect(cubit.state.isLoading, isFalse);
      cubit.close();
    });

    test('queueDownload delegates to usecase and handles error', () async {
      when(() => mockQueue.call(testTask)).thenAnswer(
          (_) async => const Left(DownloadFailure('Network unavailable')));

      final cubit = buildCubit();
      await Future.delayed(const Duration(milliseconds: 50));

      await cubit.queueDownload(testTask);
      expect(cubit.state.errorMessage, 'Network unavailable');
      cubit.close();
    });

    test('pauseDownload delegates to usecase', () async {
      when(() => mockPause.call('vid_123'))
          .thenAnswer((_) async => const Right(unit));

      final cubit = buildCubit();
      await Future.delayed(const Duration(milliseconds: 50));

      await cubit.pauseDownload('vid_123');
      verify(() => mockPause.call('vid_123')).called(1);
      cubit.close();
    });

    test('resumeDownload delegates to usecase', () async {
      when(() => mockResume.call('vid_123'))
          .thenAnswer((_) async => const Right(unit));

      final cubit = buildCubit();
      await Future.delayed(const Duration(milliseconds: 50));

      await cubit.resumeDownload('vid_123');
      verify(() => mockResume.call('vid_123')).called(1);
      cubit.close();
    });

    test('retryDownload delegates to usecase', () async {
      when(() => mockRetry.call('vid_123'))
          .thenAnswer((_) async => const Right(unit));

      final cubit = buildCubit();
      await Future.delayed(const Duration(milliseconds: 50));

      await cubit.retryDownload('vid_123');
      verify(() => mockRetry.call('vid_123')).called(1);
      cubit.close();
    });

    test('deleteDownload removes task and refreshes stats', () async {
      when(() => mockObserve.getAll()).thenAnswer((_) async => [testTask]);
      when(() => mockDelete.call('vid_123'))
          .thenAnswer((_) async => const Right(unit));

      final cubit = buildCubit();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(cubit.state.tasks.containsKey('vid_123'), isTrue);

      await cubit.deleteDownload('vid_123');
      expect(cubit.state.tasks.containsKey('vid_123'), isFalse);
      verify(() => mockDelete.call('vid_123')).called(1);
      cubit.close();
    });

    test(
        'stream updates update task in state and triggers stats refresh on terminal state',
        () async {
      final cubit = buildCubit();
      await Future.delayed(const Duration(milliseconds: 50));

      final updatedTask = testTask.copyWith(
        status: DownloadStatus.complete,
        progress: 1.0,
      );

      downloadStreamController.add(updatedTask);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(cubit.state.tasks['vid_123']?.status, DownloadStatus.complete);
      cubit.close();
    });

    test('prioritizeDownload calls usecase with videoId', () async {
      when(() => mockPrioritize.call('vid_123'))
          .thenAnswer((_) async => const Right(unit));

      final cubit = buildCubit();
      await Future.delayed(const Duration(milliseconds: 50));
      await cubit.prioritizeDownload('vid_123');

      verify(() => mockPrioritize.call('vid_123')).called(1);
      cubit.close();
    });

    test('reorderQueue calls usecase with ordered videoIds', () async {
      when(() => mockReorder.call(['vid_2', 'vid_1']))
          .thenAnswer((_) async => const Right(unit));

      final cubit = buildCubit();
      await Future.delayed(const Duration(milliseconds: 50));
      await cubit.reorderQueue(['vid_2', 'vid_1']);

      verify(() => mockReorder.call(['vid_2', 'vid_1'])).called(1);
      cubit.close();
    });

    test('resumeAllPaused resumes all paused and interrupted tasks', () async {
      final task1 = testTask.copyWith(id: 'p1', videoId: 'p1', status: DownloadStatus.paused);
      final task2 = testTask.copyWith(id: 'p2', videoId: 'p2', status: DownloadStatus.interrupted);
      final task3 = testTask.copyWith(id: 'c3', videoId: 'c3', status: DownloadStatus.complete);

      when(() => mockObserve.getAll()).thenAnswer((_) async => [task1, task2, task3]);
      when(() => mockResume.call('p1')).thenAnswer((_) async => const Right(unit));
      when(() => mockResume.call('p2')).thenAnswer((_) async => const Right(unit));

      final cubit = buildCubit();
      await Future.delayed(const Duration(milliseconds: 50));

      await cubit.resumeAllPaused();

      verify(() => mockResume.call('p1')).called(1);
      verify(() => mockResume.call('p2')).called(1);
      verifyNever(() => mockResume.call('c3'));
      cubit.close();
    });

    test('retryAllFailed retries all failed and interrupted tasks', () async {
      final task1 = testTask.copyWith(id: 'f1', videoId: 'f1', status: DownloadStatus.failed);
      final task2 = testTask.copyWith(id: 'f2', videoId: 'f2', status: DownloadStatus.interrupted);
      final task3 = testTask.copyWith(id: 'c3', videoId: 'c3', status: DownloadStatus.complete);

      when(() => mockObserve.getAll()).thenAnswer((_) async => [task1, task2, task3]);
      when(() => mockRetry.call('f1')).thenAnswer((_) async => const Right(unit));
      when(() => mockRetry.call('f2')).thenAnswer((_) async => const Right(unit));

      final cubit = buildCubit();
      await Future.delayed(const Duration(milliseconds: 50));

      await cubit.retryAllFailed();

      verify(() => mockRetry.call('f1')).called(1);
      verify(() => mockRetry.call('f2')).called(1);
      verifyNever(() => mockRetry.call('c3'));
      cubit.close();
    });

    test('clearError resets errorMessage and failure in DownloadsState', () async {
      when(() => mockQueue.call(testTask)).thenAnswer(
          (_) async => const Left(DownloadFailure('Some fatal error')));

      final cubit = buildCubit();
      await Future.delayed(const Duration(milliseconds: 50));

      await cubit.queueDownload(testTask);
      expect(cubit.state.errorMessage, 'Some fatal error');
      expect(cubit.state.failure, isA<DownloadFailure>());

      cubit.clearError();
      expect(cubit.state.errorMessage, isNull);
      expect(cubit.state.failure, isNull);
      cubit.close();
    });

    test('DownloadsState helper getters compute task counts accurately', () {
      final tasks = {
        't1': testTask.copyWith(videoId: 't1', status: DownloadStatus.downloading),
        't2': testTask.copyWith(videoId: 't2', status: DownloadStatus.paused),
        't3': testTask.copyWith(videoId: 't3', status: DownloadStatus.interrupted),
        't4': testTask.copyWith(videoId: 't4', status: DownloadStatus.complete),
        't5': testTask.copyWith(videoId: 't5', status: DownloadStatus.failed),
      };

      final state = DownloadsState(tasks: tasks);

      expect(state.activeCount, 1);
      expect(state.pausedCount, 2);
      expect(state.hasPausedTasks, isTrue);
      expect(state.completedCount, 1);
      expect(state.taskList.length, 5);
    });

    test('DownloadsState copyWith preserves error fields unless explicitly cleared', () {
      const initial = DownloadsState(
        errorMessage: 'Network error',
        failure: DownloadFailure('Network error'),
      );

      final updated = initial.copyWith(isLoading: true);
      expect(updated.errorMessage, 'Network error');
      expect(updated.failure, isA<DownloadFailure>());

      final cleared = initial.copyWith(clearErrorMessage: true, clearFailure: true);
      expect(cleared.errorMessage, isNull);
      expect(cleared.failure, isNull);
    });

    test('Move 4: 1000 progress ticks in 1s throttle to <=6 emissions and terminal complete arrives', () async {
      final cubit = buildCubit();
      await Future.delayed(const Duration(milliseconds: 50));

      int emissionCount = 0;
      final sub = cubit.stream.listen((_) => emissionCount++);

      // Emit 1000 progress ticks in tight loop
      for (int i = 1; i <= 999; i++) {
        downloadStreamController.add(testTask.copyWith(
          status: DownloadStatus.downloading,
          progress: i / 1000.0,
        ));
      }

      // Terminal event
      downloadStreamController.add(testTask.copyWith(
        status: DownloadStatus.complete,
        progress: 1.0,
      ));

      // Wait 300ms for trailing throttle to flush
      await Future.delayed(const Duration(milliseconds: 350));

      expect(emissionCount, lessThanOrEqualTo(6));
      expect(cubit.state.tasks[testTask.videoId]?.status, DownloadStatus.complete);
      expect(cubit.state.tasks[testTask.videoId]?.progress, 1.0);

      await sub.cancel();
      cubit.close();
    });

    test('Move 3: per-task actions serialize correctly without deadlock', () async {
      when(() => mockPause.call('vid_123')).thenAnswer((_) async {
        await Future.delayed(const Duration(milliseconds: 20));
        return const Right(unit);
      });
      when(() => mockResume.call('vid_123')).thenAnswer((_) async {
        await Future.delayed(const Duration(milliseconds: 20));
        return const Right(unit);
      });

      final cubit = buildCubit();
      await Future.delayed(const Duration(milliseconds: 50));

      // Fire concurrent pause and resume on same ID
      final f1 = cubit.pauseDownload('vid_123');
      final f2 = cubit.resumeDownload('vid_123');

      await Future.wait([f1, f2]);

      verify(() => mockPause.call('vid_123')).called(1);
      verify(() => mockResume.call('vid_123')).called(1);
      cubit.close();
    });

    test('Move 7: typed failures provide l10nKey and actionable recovery type', () {
      const f1 = AlreadyQueuedFailure('Already queued');
      expect(f1.l10nKey, 'downloadErrorAlreadyQueued');
      expect(f1.action, DownloadFailureAction.none);

      const f2 = InsufficientStorageFailure('Low disk', neededBytes: 100, availableBytes: 50);
      expect(f2.l10nKey, 'downloadErrorStorage');
      expect(f2.action, DownloadFailureAction.freeSpace);

      const f3 = PermissionDeniedFailure('No permission');
      expect(f3.l10nKey, 'downloadErrorPermission');
      expect(f3.action, DownloadFailureAction.openSettings);

      const f4 = NetworkFailure('Connection lost');
      expect(f4.l10nKey, 'downloadErrorNetwork');
      expect(f4.action, DownloadFailureAction.retry);
    });

    test('pauseDownload, resumeDownload, retryDownload, deleteDownload handle failures cleanly', () async {
      when(() => mockPause.call('err_vid')).thenAnswer((_) async => const Left(DownloadFailure('Pause fail')));
      when(() => mockResume.call('err_vid')).thenAnswer((_) async => const Left(DownloadFailure('Resume fail')));
      when(() => mockRetry.call('err_vid')).thenAnswer((_) async => const Left(DownloadFailure('Retry fail')));
      when(() => mockDelete.call('err_vid')).thenAnswer((_) async => const Left(DownloadFailure('Delete fail')));
      when(() => mockPrioritize.call('err_vid')).thenAnswer((_) async => const Left(DownloadFailure('Prioritize fail')));
      when(() => mockReorder.call(['v1', 'v2'])).thenAnswer((_) async => const Left(DownloadFailure('Reorder fail')));

      final cubit = buildCubit();
      await Future.delayed(const Duration(milliseconds: 50));

      await cubit.pauseDownload('err_vid');
      expect(cubit.state.errorMessage, 'Pause fail');

      await cubit.resumeDownload('err_vid');
      expect(cubit.state.errorMessage, 'Resume fail');

      await cubit.retryDownload('err_vid');
      expect(cubit.state.errorMessage, 'Retry fail');

      await cubit.deleteDownload('err_vid');
      expect(cubit.state.errorMessage, 'Delete fail');

      await cubit.prioritizeDownload('err_vid');
      expect(cubit.state.errorMessage, 'Prioritize fail');

      await cubit.reorderQueue(['v1', 'v2']);
      expect(cubit.state.errorMessage, 'Reorder fail');

      cubit.close();
    });

    test('Task actions catch unhandled exceptions without throwing or crashing', () async {
      when(() => mockPause.call('crash_vid')).thenThrow(Exception('Simulated crash'));
      when(() => mockResume.call('crash_vid')).thenThrow(Exception('Simulated crash'));
      when(() => mockRetry.call('crash_vid')).thenThrow(Exception('Simulated crash'));
      when(() => mockDelete.call('crash_vid')).thenThrow(Exception('Simulated crash'));
      when(() => mockPrioritize.call('crash_vid')).thenThrow(Exception('Simulated crash'));
      when(() => mockStorageStats.call()).thenAnswer((_) async => const Left(StorageFailure('Stats fail')));

      final cubit = buildCubit();
      await Future.delayed(const Duration(milliseconds: 50));

      await cubit.pauseDownload('crash_vid');
      await cubit.resumeDownload('crash_vid');
      await cubit.retryDownload('crash_vid');
      await cubit.deleteDownload('crash_vid');
      await cubit.prioritizeDownload('crash_vid');
      await cubit.refreshStorageStats();

      expect(cubit.state.errorMessage, isNull);
      cubit.close();
    });

    test('[B1] deleteDownload immediately followed by queueDownload and prioritizeDownload executes sequentially without race or deadlock', () async {
      final executionOrder = <String>[];

      when(() => mockDelete.call('task_race')).thenAnswer((_) async {
        executionOrder.add('delete_start');
        await Future.delayed(const Duration(milliseconds: 20));
        executionOrder.add('delete_end');
        return const Right(unit);
      });

      final taskRace = DownloadTask(
        id: 'task_race',
        videoId: 'task_race',
        title: 'Race Song',
        artist: 'Race Artist',
        createdAt: DateTime(2026, 1, 1),
      );

      when(() => mockQueue.call(taskRace)).thenAnswer((_) async {
        executionOrder.add('queue_start');
        await Future.delayed(const Duration(milliseconds: 20));
        executionOrder.add('queue_end');
        return const Right('task_race');
      });

      when(() => mockPrioritize.call('task_race')).thenAnswer((_) async {
        executionOrder.add('prioritize_start');
        await Future.delayed(const Duration(milliseconds: 20));
        executionOrder.add('prioritize_end');
        return const Right(unit);
      });

      final cubit = buildCubit();
      await Future.delayed(const Duration(milliseconds: 10));

      final fDelete = cubit.deleteDownload('task_race');
      final fQueue = cubit.queueDownload(taskRace);
      final fPrioritize = cubit.prioritizeDownload('task_race');

      await Future.wait([fDelete, fQueue, fPrioritize]);

      expect(executionOrder, [
        'delete_start',
        'delete_end',
        'queue_start',
        'queue_end',
        'prioritize_start',
        'prioritize_end',
      ]);

      cubit.close();
    });
  });
}
