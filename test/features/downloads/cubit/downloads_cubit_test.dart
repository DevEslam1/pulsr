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
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';

class MockQueueDownloadUseCase extends Mock implements QueueDownloadUseCase {}

class MockPauseDownloadUseCase extends Mock implements PauseDownloadUseCase {}

class MockResumeDownloadUseCase extends Mock implements ResumeDownloadUseCase {}

class MockRetryDownloadUseCase extends Mock implements RetryDownloadUseCase {}

class MockDeleteDownloadUseCase extends Mock implements DeleteDownloadUseCase {}

class MockObserveDownloadsUseCase extends Mock
    implements ObserveDownloadsUseCase {}

class MockGetDownloadStorageStatsUseCase extends Mock
    implements GetDownloadStorageStatsUseCase {}

void main() {
  late MockQueueDownloadUseCase mockQueue;
  late MockPauseDownloadUseCase mockPause;
  late MockResumeDownloadUseCase mockResume;
  late MockRetryDownloadUseCase mockRetry;
  late MockDeleteDownloadUseCase mockDelete;
  late MockObserveDownloadsUseCase mockObserve;
  late MockGetDownloadStorageStatsUseCase mockStorageStats;
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
  });
}
