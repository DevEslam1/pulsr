// test/domain/usecases/download_usecases_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/repositories/download_repository_interface.dart';
import 'package:pulsr/domain/usecases/delete_download.dart';
import 'package:pulsr/domain/usecases/get_download_storage_stats.dart';
import 'package:pulsr/domain/usecases/observe_downloads.dart';
import 'package:pulsr/domain/usecases/pause_download.dart';
import 'package:pulsr/domain/usecases/queue_download.dart';
import 'package:pulsr/domain/usecases/resume_download.dart';
import 'package:pulsr/domain/usecases/retry_download.dart';

class MockDownloadRepository extends Mock implements IDownloadRepository {}

void main() {
  late MockDownloadRepository mockRepo;
  late QueueDownloadUseCase queueUseCase;
  late PauseDownloadUseCase pauseUseCase;
  late ResumeDownloadUseCase resumeUseCase;
  late RetryDownloadUseCase retryUseCase;
  late DeleteDownloadUseCase deleteUseCase;
  late ObserveDownloadsUseCase observeUseCase;
  late GetDownloadStorageStatsUseCase storageStatsUseCase;

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
  });

  group('Download UseCases', () {
    test('QueueDownloadUseCase delegates to repository', () async {
      when(() => mockRepo.queueDownload(testTask))
          .thenAnswer((_) async => const Right('test_id_1'));

      final result = await queueUseCase(testTask);
      expect(result, const Right('test_id_1'));
      verify(() => mockRepo.queueDownload(testTask)).called(1);
    });

    test('PauseDownloadUseCase delegates to repository', () async {
      when(() => mockRepo.pauseDownload('vid_123'))
          .thenAnswer((_) async => const Right(unit));

      final result = await pauseUseCase('vid_123');
      expect(result, const Right(unit));
      verify(() => mockRepo.pauseDownload('vid_123')).called(1);
    });

    test('ResumeDownloadUseCase delegates to repository', () async {
      when(() => mockRepo.resumeDownload('vid_123'))
          .thenAnswer((_) async => const Right(unit));

      final result = await resumeUseCase('vid_123');
      expect(result, const Right(unit));
      verify(() => mockRepo.resumeDownload('vid_123')).called(1);
    });

    test('RetryDownloadUseCase delegates to repository', () async {
      when(() => mockRepo.retryDownload('vid_123'))
          .thenAnswer((_) async => const Right(unit));

      final result = await retryUseCase('vid_123');
      expect(result, const Right(unit));
      verify(() => mockRepo.retryDownload('vid_123')).called(1);
    });

    test('DeleteDownloadUseCase delegates to repository', () async {
      when(() => mockRepo.deleteDownload('vid_123'))
          .thenAnswer((_) async => const Right(unit));

      final result = await deleteUseCase('vid_123');
      expect(result, const Right(unit));
      verify(() => mockRepo.deleteDownload('vid_123')).called(1);
    });

    test('ObserveDownloadsUseCase provides stream from repository', () async {
      final controller = StreamController<DownloadTask>();
      when(() => mockRepo.observeDownloads())
          .thenAnswer((_) => controller.stream);

      final stream = observeUseCase();
      expectLater(stream, emits(testTask));
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
      when(() => mockRepo.getStorageStats())
          .thenAnswer((_) async => const Right(stats));

      final result = await storageStatsUseCase();
      expect(result, const Right(stats));
      verify(() => mockRepo.getStorageStats()).called(1);
    });
  });
}
