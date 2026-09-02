// test/features/downloads/cubit/downloads_transient_lifecycle_test.dart
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

  group('Transient Error Lifecycle & Terminal Flush Tests', () {
    test(
      'Transient error is cleared upon explicit clearError() call',
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

        final task = DownloadTask(
          id: 'task_err',
          videoId: 'vid_err',
          title: 'Error Song',
          artist: 'Artist',
          createdAt: DateTime.now(),
        );

        when(
          () => mockQueue.call(task),
        ).thenAnswer((_) async => const Left(NetworkFailure('Network down')));

        final cubit = DownloadsCubit(
          mockQueue,
          mockPause,
          mockResume,
          mockRetry,
          mockDelete,
          mockObserve,
          mockStorageStats,
        );

        await cubit.queueDownload(task);
        expect(cubit.state.errorMessage, equals('Network down'));
        expect(cubit.state.failure, isA<NetworkFailure>());

        // Navigation / dialog dismissal clears transient error
        cubit.clearError();
        expect(cubit.state.errorMessage, isNull);
        expect(cubit.state.failure, isNull);

        await cubit.close();
        await streamCtrl.close();
      },
    );

    test(
      'Terminal FAILED event flushes within bounded <= 350ms window',
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

        final cubit = DownloadsCubit(
          mockQueue,
          mockPause,
          mockResume,
          mockRetry,
          mockDelete,
          mockObserve,
          mockStorageStats,
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final failedTask = DownloadTask(
          id: 'task_flush',
          videoId: 'vid_flush',
          title: 'Flush Song',
          artist: 'Artist',
          status: DownloadStatus.failed,
          error: 'Fatal decode error',
          createdAt: DateTime.now(),
        );

        final stopwatch = Stopwatch()..start();
        streamCtrl.add(failedTask);

        // Await arrival
        while (cubit.state.byId('task_flush')?.status !=
                DownloadStatus.failed &&
            stopwatch.elapsedMilliseconds < 1000) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
        stopwatch.stop();

        expect(
          cubit.state.byId('task_flush')?.status,
          equals(DownloadStatus.failed),
        );
        expect(
          stopwatch.elapsedMilliseconds,
          lessThanOrEqualTo(350),
          reason: 'Terminal failed event must flush within 350ms',
        );

        await cubit.close();
        await streamCtrl.close();
      },
    );
  });
}
