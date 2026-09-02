// test/domain/usecases/download_usecases_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/repositories/download_repository_interface.dart';
import 'package:pulsr/domain/usecases/download_lifecycle_usecases.dart';
import 'package:pulsr/domain/usecases/download_query_usecases.dart';
import 'package:pulsr/domain/usecases/download_queue_usecases.dart';
import 'package:pulsr/core/errors/failures.dart';

class MockDownloadRepository extends Mock implements IDownloadRepository {}

void main() {
  late MockDownloadRepository mockRepo;

  setUpAll(() {
    // `any()` matchers on non-primitive parameters require registered
    // fallback values (mocktail).
    registerFallbackValue(
      DownloadTask(
        id: 'fallback',
        videoId: 'fallback',
        title: 'Fallback',
        artist: 'Fallback',
        createdAt: DateTime.now(),
      ),
    );
    registerFallbackValue(<String>[]);
  });
  late QueueDownloadUseCase queueUseCase;
  late PauseDownloadUseCase pauseUseCase;
  late ResumeDownloadUseCase resumeUseCase;
  late RetryDownloadUseCase retryUseCase;
  late DeleteDownloadUseCase deleteUseCase;
  late ObserveDownloadsUseCase observeUseCase;
  late GetDownloadStorageStatsUseCase storageStatsUseCase;
  late PrioritizeDownloadUseCase prioritizeUseCase;
  late ReorderDownloadsUseCase reorderUseCase;

  final testTask = DownloadTask(
    id: 'test_id_1',
    videoId: 'vid_123',
    title: 'Song Title',
    artist: 'Artist Name',
    createdAt: DateTime(2026, 1, 1),
  );

  setUp(() {
    mockRepo = MockDownloadRepository();
    queueUseCase = QueueDownloadUseCase(mockRepo);
    pauseUseCase = PauseDownloadUseCase(mockRepo);
    resumeUseCase = ResumeDownloadUseCase(mockRepo);
    retryUseCase = RetryDownloadUseCase(mockRepo);
    deleteUseCase = DeleteDownloadUseCase(mockRepo);
    observeUseCase = ObserveDownloadsUseCase(mockRepo);
    storageStatsUseCase = GetDownloadStorageStatsUseCase(mockRepo);
    prioritizeUseCase = PrioritizeDownloadUseCase(mockRepo);
    reorderUseCase = ReorderDownloadsUseCase(mockRepo);
  });

  group('Download UseCases', () {
    test('QueueDownloadUseCase delegates to repository', () async {
      when(
        () => mockRepo.queueDownload(testTask),
      ).thenAnswer((_) async => const Right<AppFailure, String>('test_id_1'));

      final result = await queueUseCase(testTask);
      expect(result, const Right<AppFailure, String>('test_id_1'));
      verify(() => mockRepo.queueDownload(testTask)).called(1);
    });

    test('PauseDownloadUseCase delegates to repository', () async {
      when(
        () => mockRepo.pauseDownload('vid_123'),
      ).thenAnswer((_) async => const Right<AppFailure, Unit>(unit));

      final result = await pauseUseCase('vid_123');
      expect(result, const Right<AppFailure, Unit>(unit));
      verify(() => mockRepo.pauseDownload('vid_123')).called(1);
    });

    test('ResumeDownloadUseCase delegates to repository', () async {
      when(
        () => mockRepo.resumeDownload('vid_123'),
      ).thenAnswer((_) async => const Right<AppFailure, Unit>(unit));

      final result = await resumeUseCase('vid_123');
      expect(result, const Right<AppFailure, Unit>(unit));
      verify(() => mockRepo.resumeDownload('vid_123')).called(1);
    });

    test('RetryDownloadUseCase delegates to repository', () async {
      when(
        () => mockRepo.retryDownload('vid_123'),
      ).thenAnswer((_) async => const Right<AppFailure, Unit>(unit));

      final result = await retryUseCase('vid_123');
      expect(result, const Right<AppFailure, Unit>(unit));
      verify(() => mockRepo.retryDownload('vid_123')).called(1);
    });

    test('DeleteDownloadUseCase delegates to repository', () async {
      when(
        () => mockRepo.deleteDownload('vid_123'),
      ).thenAnswer((_) async => const Right<AppFailure, Unit>(unit));

      final result = await deleteUseCase('vid_123');
      expect(result, const Right<AppFailure, Unit>(unit));
      verify(() => mockRepo.deleteDownload('vid_123')).called(1);
    });

    test('PrioritizeDownloadUseCase delegates to repository', () async {
      when(
        () => mockRepo.prioritizeDownload('vid_123'),
      ).thenAnswer((_) async => const Right<AppFailure, Unit>(unit));

      final result = await prioritizeUseCase('vid_123');
      expect(result, const Right<AppFailure, Unit>(unit));
      verify(() => mockRepo.prioritizeDownload('vid_123')).called(1);
    });

    test('ReorderDownloadsUseCase delegates to repository', () async {
      const ids = ['vid_1', 'vid_2', 'vid_3'];
      when(
        () => mockRepo.reorderQueue(ids),
      ).thenAnswer((_) async => const Right<AppFailure, Unit>(unit));

      final result = await reorderUseCase(ids);
      expect(result, const Right<AppFailure, Unit>(unit));
      verify(() => mockRepo.reorderQueue(ids)).called(1);
    });

    test('ObserveDownloadsUseCase provides stream from repository', () async {
      final controller = StreamController<DownloadTask>();
      when(
        () => mockRepo.observeDownloads(),
      ).thenAnswer((_) => controller.stream);

      final stream = observeUseCase();
      unawaited(expectLater(stream, emits(testTask)));
      controller.add(testTask);
      await controller.close();
    });

    test('GetDownloadStorageStatsUseCase delegates to repository', () async {
      const stats = StorageStats(
        usedBytes: 1000,
        freeBytes: 9000,
        totalBytes: 10000,
        downloadedSongsCount: 5,
      );
      when(
        () => mockRepo.getStorageStats(),
      ).thenAnswer((_) async => const Right<AppFailure, StorageStats>(stats));

      final result = await storageStatsUseCase();
      expect(result, const Right<AppFailure, StorageStats>(stats));
      verify(() => mockRepo.getStorageStats()).called(1);
    });

    group('ValidationFailure on null/empty input', () {
      test(
        'QueueDownloadUseCase rejects empty videoId and empty title',
        () async {
          final noVideoId = testTask.copyWith(videoId: '');
          final noTitle = testTask.copyWith(title: '  ');

          final r1 = await queueUseCase(noVideoId);
          final r2 = await queueUseCase(noTitle);

          expect(r1, isA<Left<AppFailure, String>>());
          expect((r1 as Left).value, isA<ValidationFailure>());
          expect(r2, isA<Left<AppFailure, String>>());
          expect((r2 as Left).value, isA<ValidationFailure>());
          verifyNever(() => mockRepo.queueDownload(any()));
        },
      );

      test('PauseDownloadUseCase rejects empty videoId', () async {
        final result = await pauseUseCase('  ');
        expect(result, isA<Left<AppFailure, Unit>>());
        expect((result as Left).value, isA<ValidationFailure>());
        verifyNever(() => mockRepo.pauseDownload(any()));
      });

      test('ResumeDownloadUseCase rejects empty videoId', () async {
        final result = await resumeUseCase('');
        expect(result, isA<Left<AppFailure, Unit>>());
        expect((result as Left).value, isA<ValidationFailure>());
        verifyNever(() => mockRepo.resumeDownload(any()));
      });

      test('RetryDownloadUseCase rejects empty videoId', () async {
        final result = await retryUseCase(' \n ');
        expect(result, isA<Left<AppFailure, Unit>>());
        expect((result as Left).value, isA<ValidationFailure>());
        verifyNever(() => mockRepo.retryDownload(any()));
      });

      test('DeleteDownloadUseCase rejects empty videoId', () async {
        final result = await deleteUseCase('');
        expect(result, isA<Left<AppFailure, Unit>>());
        expect((result as Left).value, isA<ValidationFailure>());
        verifyNever(() => mockRepo.deleteDownload(any()));
      });

      test('PrioritizeDownloadUseCase rejects empty videoId', () async {
        final result = await prioritizeUseCase('');
        expect(result, isA<Left<AppFailure, Unit>>());
        expect((result as Left).value, isA<ValidationFailure>());
        verifyNever(() => mockRepo.prioritizeDownload(any()));
      });

      test('ReorderDownloadsUseCase rejects empty ordered list', () async {
        final result = await reorderUseCase(const []);
        expect(result, isA<Left<AppFailure, Unit>>());
        expect((result as Left).value, isA<ValidationFailure>());
        verifyNever(() => mockRepo.reorderQueue(any()));
      });

      test(
        'QueueDownloadsBatchUseCase returns empty result for empty input',
        () async {
          final useCase = QueueDownloadsBatchUseCase(mockRepo);
          expect(await useCase(const []), isEmpty);
          verifyNever(() => mockRepo.queueDownload(any()));
        },
      );
    });

    group('Repository failure propagation', () {
      test('QueueDownloadUseCase propagates repository failure', () async {
        when(
          () => mockRepo.queueDownload(testTask),
        ).thenAnswer((_) async => const Left(DownloadFailure('No space')));

        final result = await queueUseCase(testTask);
        expect(result, isA<Left<AppFailure, String>>());
        expect((result as Left).value, isA<DownloadFailure>());
      });

      test('PauseDownloadUseCase propagates repository failure', () async {
        when(
          () => mockRepo.pauseDownload('vid_123'),
        ).thenAnswer((_) async => const Left(DownloadFailure('No task')));

        final result = await pauseUseCase('vid_123');
        expect(result, isA<Left<AppFailure, Unit>>());
        expect((result as Left).value, isA<DownloadFailure>());
      });

      test('ResumeDownloadUseCase propagates repository failure', () async {
        when(
          () => mockRepo.resumeDownload('vid_123'),
        ).thenAnswer((_) async => const Left(DownloadFailure('No task')));

        final result = await resumeUseCase('vid_123');
        expect(result, isA<Left<AppFailure, Unit>>());
        expect((result as Left).value, isA<DownloadFailure>());
      });

      test('RetryDownloadUseCase propagates repository failure', () async {
        when(
          () => mockRepo.retryDownload('vid_123'),
        ).thenAnswer((_) async => const Left(DownloadFailure('No task')));

        final result = await retryUseCase('vid_123');
        expect(result, isA<Left<AppFailure, Unit>>());
        expect((result as Left).value, isA<DownloadFailure>());
      });

      test('DeleteDownloadUseCase propagates repository failure', () async {
        when(
          () => mockRepo.deleteDownload('vid_123'),
        ).thenAnswer((_) async => const Left(DownloadFailure('No task')));

        final result = await deleteUseCase('vid_123');
        expect(result, isA<Left<AppFailure, Unit>>());
        expect((result as Left).value, isA<DownloadFailure>());
      });

      test('PrioritizeDownloadUseCase propagates repository failure', () async {
        when(
          () => mockRepo.prioritizeDownload('vid_123'),
        ).thenAnswer((_) async => const Left(DownloadFailure('No task')));

        final result = await prioritizeUseCase('vid_123');
        expect(result, isA<Left<AppFailure, Unit>>());
        expect((result as Left).value, isA<DownloadFailure>());
      });

      test('ReorderDownloadsUseCase propagates repository failure', () async {
        when(
          () => mockRepo.reorderQueue(['vid_1']),
        ).thenAnswer((_) async => const Left(DownloadFailure('No task')));

        final result = await reorderUseCase(['vid_1']);
        expect(result, isA<Left<AppFailure, Unit>>());
        expect((result as Left).value, isA<DownloadFailure>());
      });

      test(
        'GetDownloadStorageStatsUseCase propagates repository failure',
        () async {
          when(
            () => mockRepo.getStorageStats(),
          ).thenAnswer((_) async => const Left(StorageFailure('No stats')));

          final result = await storageStatsUseCase();
          expect(result, isA<Left<AppFailure, StorageStats>>());
          expect((result as Left).value, isA<StorageFailure>());
        },
      );
    });

    group('QueueDownloadsBatchUseCase', () {
      test(
        'executeWithBatchResult aggregates queued, skipped and failed ids',
        () async {
          final useCase = QueueDownloadsBatchUseCase(mockRepo);
          final t1 = testTask.copyWith(id: 't1', videoId: 'v1');
          final t2 = testTask.copyWith(id: 't2', videoId: 'v2');
          final t3 = testTask.copyWith(id: 't3', videoId: 'v3');

          when(
            () => mockRepo.queueDownload(t1),
          ).thenAnswer((_) async => const Right('t1'));
          when(() => mockRepo.queueDownload(t2)).thenAnswer(
            (_) async => const Left(AlreadyQueuedFailure('Already queued')),
          );
          when(() => mockRepo.queueDownload(t3)).thenAnswer(
            (_) async => const Left(InsufficientStorageFailure('Full')),
          );

          final result = await useCase.executeWithBatchResult([t1, t2, t3]);

          expect(result.totalCount, 3);
          expect(result.queuedCount, 1);
          expect(result.skippedDuplicatesCount, 1);
          expect(result.taskIds, ['t1']);
          expect(result.failedIds.keys, contains('t3'));
          expect(result.failures.single, isA<InsufficientStorageFailure>());
          expect(result.hasFailures, isTrue);
          expect(result.allSucceeded, isFalse);
        },
      );
    });
  });
}
