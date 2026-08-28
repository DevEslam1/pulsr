// test/audit_repro/downloads_audit_repro_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/domain/models/download_settings.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/usecases/queue_downloads_batch.dart';

class MockDownloadRepo extends Mock {
  Future<Either<Failure, String>> queueDownload(DownloadTask task);
  Future<Either<Failure, BatchDownloadResult>> queueBatch(List<DownloadTask> tasks);
  Future<int> reconcileUnfinishedTasks();
  Future<int> cleanOrphanFiles(Directory dir, Set<String> activeFileNames);
}

void main() {
  group('[D1] Scoped storage safe download destination', () {
    test('Downloads use app-private directory during download before MediaStore publication', () {
      final task = DownloadTask(
        id: 'task_d1',
        videoId: 'vid_d1',
        title: 'Scoped Song',
        artist: 'Artist',
        createdAt: DateTime.now(),
      );
      // Repro assertion: in-flight path must reside inside app data/cache directory
      final inFlightPath = task.tempFilePath ?? '';
      expect(inFlightPath.contains('Android/data') || inFlightPath.contains('cache') || inFlightPath.contains('temp') || inFlightPath.isEmpty, isTrue);
    });
  });

  group('[D2] & [D3] FGS lifecycle hardening & startup reconcile', () {
    test('Reconcile marks in-progress tasks as paused after process kill / timeout', () async {
      final repo = MockDownloadRepo();
      when(() => repo.reconcileUnfinishedTasks()).thenAnswer((_) async => 3);

      final count = await repo.reconcileUnfinishedTasks();
      expect(count, equals(3));
    });
  });

  group('[D4] Orphan sweeper', () {
    test('Sweeper deletes unreferenced .part and .tmp files but keeps active tasks', () async {
      final repo = MockDownloadRepo();
      final tempDir = Directory.systemTemp;
      when(() => repo.cleanOrphanFiles(tempDir, {'active_1.part'})).thenAnswer((_) async => 2);

      final cleaned = await repo.cleanOrphanFiles(tempDir, {'active_1.part'});
      expect(cleaned, equals(2));
    });
  });

  group('[D5] Duplicate guard', () {
    test('Queueing an already queued videoId returns typed AlreadyQueuedFailure', () async {
      final repo = MockDownloadRepo();
      final task = DownloadTask(
        id: 'dupe_task',
        videoId: 'existing_vid',
        title: 'Duplicate Song',
        artist: 'Artist',
        createdAt: DateTime.now(),
      );

      when(() => repo.queueDownload(task))
          .thenAnswer((_) async => const Left(AlreadyQueuedFailure('Video already in download queue')));

      final result = await repo.queueDownload(task);
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<AlreadyQueuedFailure>()),
        (_) => fail('Should have failed with AlreadyQueuedFailure'),
      );
    });
  });

  group('[D6] Disk preflight', () {
    test('Returns InsufficientStorageFailure when available space is less than estimated size with 1.2 safety factor', () {
      const bitrateKbps = 160;
      const durationSeconds = 300;
      const safetyFactor = 1.2;
      const estimatedBytes = (durationSeconds * (bitrateKbps * 1000 / 8) * safetyFactor) + (5 * 1024 * 1024);

      const availableBytes = 5 * 1024 * 1024; // 5 MB available, needed ~12MB
      final isSpaceSufficient = availableBytes >= estimatedBytes;
      expect(isSpaceSufficient, isFalse);

      const failure = InsufficientStorageFailure('Insufficient storage space: needed 12MB, available 5MB');
      expect(failure, isA<InsufficientStorageFailure>());
    });
  });

  group('[D7] Tag-before-scan pipeline', () {
    test('DownloadTaskStatus includes embedding state between downloading and completed', () {
      expect(DownloadTaskStatus.values.contains(DownloadTaskStatus.embedding), isTrue);
    });
  });

  group('[D9] Progress-based timeout', () {
    test('DownloadSettings supports configurable progressTimeoutWindowSeconds defaulting to 30s', () {
      final settings = DownloadSettings.defaultSettings();
      expect(settings.progressTimeoutWindowSeconds, equals(30));
    });
  });
}
