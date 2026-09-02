// test/features/downloads/cubit/downloads_batch_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/usecases/download_lifecycle_usecases.dart';
import 'package:pulsr/domain/usecases/download_query_usecases.dart';
import 'package:pulsr/domain/usecases/download_queue_usecases.dart';
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

class MockQueueDownloadsBatchUseCase extends Mock
    implements QueueDownloadsBatchUseCase {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      DownloadTask(
        id: 'fallback',
        videoId: 'fallback',
        title: 'Fallback',
        artist: 'Fallback',
        createdAt: DateTime.now(),
      ),
    );
  });

  group('Downloads Batch Partial Outcomes & failedIds Contract', () {
    test(
      'Batch of 3 with middle failure queues 2 and populates failedIds with typed failure',
      () async {
        final mockQueue = MockQueueDownloadUseCase();
        final mockPause = MockPauseDownloadUseCase();
        final mockResume = MockResumeDownloadUseCase();
        final mockRetry = MockRetryDownloadUseCase();
        final mockDelete = MockDeleteDownloadUseCase();
        final mockObserve = MockObserveDownloadsUseCase();
        final mockStorageStats = MockGetDownloadStorageStatsUseCase();
        final streamCtrl = StreamController<DownloadTask>.broadcast();

        when(() => mockObserve.call()).thenAnswer((_) => streamCtrl.stream);
        when(() => mockObserve.getAll()).thenAnswer((_) async => []);
        when(
          () => mockStorageStats.call(),
        ).thenAnswer((_) async => const Right(StorageStats()));

        final task1 = DownloadTask(
          id: 'task_1',
          videoId: 'vid_1',
          title: 'Song 1',
          artist: 'Artist',
          createdAt: DateTime.now(),
        );
        final task2 = DownloadTask(
          id: 'task_2',
          videoId: 'vid_2',
          title: 'Song 2',
          artist: 'Artist',
          createdAt: DateTime.now(),
        );
        final task3 = DownloadTask(
          id: 'task_3',
          videoId: 'vid_3',
          title: 'Song 3',
          artist: 'Artist',
          createdAt: DateTime.now(),
        );

        when(() => mockQueue.call(any())).thenAnswer((inv) async {
          final t = inv.positionalArguments[0] as DownloadTask;
          if (t.id == 'task_2' || t.videoId == 'vid_2') {
            return const Left(InsufficientStorageFailure('Storage full'));
          }
          return Right(t.id);
        });

        final cubit = DownloadsCubit(
          mockQueue,
          mockPause,
          mockResume,
          mockRetry,
          mockDelete,
          mockObserve,
          mockStorageStats,
        );

        final result = await cubit.queueBatch([task1, task2, task3]);

        expect(result.totalCount, equals(3));
        expect(result.queuedCount, equals(2));
        expect(result.taskIds, containsAll(['task_1', 'task_3']));
        expect(result.hasFailures, isTrue);
        expect(result.failedIds.containsKey('task_2'), isTrue);
        expect(result.failedIds['task_2'], isA<InsufficientStorageFailure>());
        expect(result.failures.length, equals(1));
        expect(result.failures.first, isA<InsufficientStorageFailure>());

        await cubit.close();
        await streamCtrl.close();
      },
    );

    test(
      'Batch use case path surfaces first failure and reports per-item result',
      () async {
        final mockQueue = MockQueueDownloadUseCase();
        final mockPause = MockPauseDownloadUseCase();
        final mockResume = MockResumeDownloadUseCase();
        final mockRetry = MockRetryDownloadUseCase();
        final mockDelete = MockDeleteDownloadUseCase();
        final mockObserve = MockObserveDownloadsUseCase();
        final mockStorageStats = MockGetDownloadStorageStatsUseCase();
        final mockBatchUseCase = MockQueueDownloadsBatchUseCase();
        final streamCtrl = StreamController<DownloadTask>.broadcast();

        when(() => mockObserve.call()).thenAnswer((_) => streamCtrl.stream);
        when(() => mockObserve.getAll()).thenAnswer((_) async => []);
        when(
          () => mockStorageStats.call(),
        ).thenAnswer((_) async => const Right(StorageStats()));

        final task1 = DownloadTask(
          id: 'b_task_1',
          videoId: 'b_vid_1',
          title: 'Batch Song 1',
          artist: 'Artist',
          createdAt: DateTime.now(),
        );
        final task2 = DownloadTask(
          id: 'b_task_2',
          videoId: 'b_vid_2',
          title: 'Batch Song 2',
          artist: 'Artist',
          createdAt: DateTime.now(),
        );

        when(() => mockBatchUseCase.executeWithBatchResult(any())).thenAnswer(
          (_) async => BatchDownloadResult(
            totalCount: 2,
            queuedCount: 1,
            skippedDuplicatesCount: 0,
            taskIds: ['b_task_1'],
            failedIds: {
              'b_task_2': const InsufficientStorageFailure('Storage full'),
            },
            failures: const [InsufficientStorageFailure('Storage full')],
          ),
        );

        final cubit = DownloadsCubit(
          mockQueue,
          mockPause,
          mockResume,
          mockRetry,
          mockDelete,
          mockObserve,
          mockStorageStats,
          null, // reorder
          null, // prioritize
          mockBatchUseCase,
        );

        final result = await cubit.queueBatch([task1, task2]);

        verify(() => mockBatchUseCase.executeWithBatchResult(any())).called(1);
        expect(result.totalCount, equals(2));
        expect(result.queuedCount, equals(1));
        expect(result.failedIds['b_task_2'], isA<InsufficientStorageFailure>());
        expect(
          cubit.state.errorMessage,
          equals('Storage full'),
          reason: 'batch use case path emits one error at the end',
        );
        expect(cubit.state.failure, isA<InsufficientStorageFailure>());

        await cubit.close();
        await streamCtrl.close();
      },
    );
  });
}
