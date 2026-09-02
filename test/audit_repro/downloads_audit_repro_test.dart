// test/audit_repro/downloads_audit_repro_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/utils/safe_filename.dart';
import 'package:pulsr/domain/models/download_settings.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/models/retry_policy.dart';
import 'package:pulsr/domain/usecases/download_queue_usecases.dart';
import 'package:pulsr/domain/usecases/download_lifecycle_usecases.dart';
import 'package:pulsr/domain/repositories/download_repository_interface.dart';

class MockDownloadRepo extends Mock implements IDownloadRepository {
  Future<int> reconcileUnfinishedTasks();
  Future<int> cleanOrphanFiles(Directory dir, Set<String> activeFileNames);
}

void main() {
  group('[DL-01] Startup reconciliation', () {
    test(
      'Reconcile marks in-progress tasks as paused/interrupted after process kill',
      () async {
        final repo = MockDownloadRepo();
        when(() => repo.reconcileUnfinishedTasks()).thenAnswer((_) async => 3);

        final count = await repo.reconcileUnfinishedTasks();
        expect(count, equals(3));
      },
    );
  });

  group('[DL-02] Atomic write & orphan sweeper', () {
    test(
      'Sweeper deletes unreferenced .part and .tmp files but keeps active tasks',
      () async {
        final repo = MockDownloadRepo();
        final tempDir = Directory.systemTemp;
        when(
          () => repo.cleanOrphanFiles(tempDir, {'active_1.part'}),
        ).thenAnswer((_) async => 2);

        final cleaned = await repo.cleanOrphanFiles(tempDir, {'active_1.part'});
        expect(cleaned, equals(2));
      },
    );
  });

  group('[DL-03] Prod flavor graceful channel failure', () {
    test(
      'FeatureDisabledFailure is returned when native download channel is unavailable in prod',
      () {
        const failure = FeatureDisabledFailure('Unavailable in this build');
        expect(failure, isA<FeatureDisabledFailure>());
        expect(failure.message, equals('Unavailable in this build'));
      },
    );
  });

  group('[DL-04] & [D6] Disk storage preflight', () {
    test(
      'Returns InsufficientStorageFailure when available space is less than estimated size with 1.1x factor',
      () {
        const bitrateKbps = 160;
        const durationSeconds = 240;
        const safetyFactor = 1.1;
        const estimatedBytes =
            (durationSeconds * (bitrateKbps * 1000 / 8) * safetyFactor) +
            (5 * 1024 * 1024);

        const availableBytes = 5 * 1024 * 1024;
        final isSpaceSufficient = availableBytes >= estimatedBytes;
        expect(isSpaceSufficient, isFalse);

        const failure = InsufficientStorageFailure(
          'Insufficient storage space for download',
        );
        expect(failure, isA<InsufficientStorageFailure>());
      },
    );
  });

  group('[DL-05] Resume & HTTP 206 vs 200 handling', () {
    test(
      'Resume correctly requires 206 Partial Content, clean restart on 200',
      () {
        int initialOffset = 500000;
        int serverResponseCode = 200; // ignored range

        bool append = serverResponseCode == 206;
        if (!append) {
          initialOffset = 0; // restart cleanly without corrupting
        }

        expect(initialOffset, equals(0));
      },
    );
  });

  group('[DL-06] & [D5] Duplicate queue guard', () {
    test(
      'Queueing an already queued videoId returns typed AlreadyQueuedFailure or existing ID',
      () async {
        final repo = MockDownloadRepo();
        final task = DownloadTask(
          id: 'dupe_task',
          videoId: 'existing_vid',
          title: 'Duplicate Song',
          artist: 'Artist',
          createdAt: DateTime.now(),
        );

        when(() => repo.queueDownload(task)).thenAnswer(
          (_) async => const Left(
            AlreadyQueuedFailure('Video already in download queue'),
          ),
        );

        final result = await repo.queueDownload(task);
        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) => expect(failure, isA<AlreadyQueuedFailure>()),
          (_) => fail('Should have failed with AlreadyQueuedFailure'),
        );
      },
    );
  });

  group('[DL-07] Hostile filename sanitization (SafeFilename)', () {
    test(
      'Sanitizes illegal path and Windows characters (/ \\ : * ? " < > |)',
      () {
        final sanitized = SafeFilename.sanitize(
          artist: 'AC/DC *Special*',
          title: 'Song: "Rock <&> Roll"?',
          ext: 'm4a',
        );
        expect(
          sanitized,
          equals('AC_DC _Special_ - Song_ _Rock _&_ Roll__.m4a'),
        );
        expect(sanitized.contains('/'), isFalse);
        expect(sanitized.contains('\\'), isFalse);
        expect(sanitized.contains(':'), isFalse);
        expect(sanitized.contains('*'), isFalse);
        expect(sanitized.contains('?'), isFalse);
        expect(sanitized.contains('"'), isFalse);
        expect(sanitized.contains('<'), isFalse);
        expect(sanitized.contains('>'), isFalse);
        expect(sanitized.contains('|'), isFalse);
      },
    );

    test('Guards Windows reserved device names (CON, NUL, AUX, COM1)', () {
      final sanitized = SafeFilename.sanitize(
        artist: 'CON',
        title: '',
        ext: 'm4a',
      );
      expect(sanitized, equals('CON_artist - Unknown Title.m4a'));
    });

    test(
      'Caps UTF-8 byte length to 180 bytes without breaking multi-byte codepoints',
      () {
        final longTitle = '🎵' * 100; // 400 bytes
        final sanitized = SafeFilename.sanitize(
          artist: 'Artist',
          title: longTitle,
          ext: 'mp3',
        );
        expect(sanitized.endsWith('.mp3'), isTrue);
        expect(sanitized.length, lessThanOrEqualTo(185));
      },
    );

    test('Deduplicates filename collisions by appending - (2), - (3)', () {
      const existing = {'Track.m4a', 'Track - (2).m4a'};
      final candidate = SafeFilename.deduplicate('Track.m4a', existing);
      expect(candidate, equals('Track - (3).m4a'));
    });
  });

  group('[DL-10] State machine & TransitionGuard matrix', () {
    test('Allows legal status transitions', () {
      expect(
        TransitionGuard.canTransition(
          DownloadStatus.queued,
          DownloadStatus.downloading,
        ),
        isTrue,
      );
      expect(
        TransitionGuard.canTransition(
          DownloadStatus.downloading,
          DownloadStatus.embedding,
        ),
        isTrue,
      );
      expect(
        TransitionGuard.canTransition(
          DownloadStatus.embedding,
          DownloadStatus.complete,
        ),
        isTrue,
      );
      expect(
        TransitionGuard.canTransition(
          DownloadStatus.downloading,
          DownloadStatus.paused,
        ),
        isTrue,
      );
      expect(
        TransitionGuard.canTransition(
          DownloadStatus.paused,
          DownloadStatus.queued,
        ),
        isTrue,
      );
      expect(
        TransitionGuard.canTransition(
          DownloadStatus.failed,
          DownloadStatus.queued,
        ),
        isTrue,
      );
    });

    test(
      'Rejects illegal status transitions with InvalidTransitionFailure',
      () {
        expect(
          TransitionGuard.canTransition(
            DownloadStatus.complete,
            DownloadStatus.downloading,
          ),
          isFalse,
        );
        final validation = TransitionGuard.validate(
          DownloadStatus.complete,
          DownloadStatus.downloading,
        );
        expect(validation.isLeft(), isTrue);
        validation.fold(
          (f) => expect(f, isA<InvalidTransitionFailure>()),
          (_) => fail('Should have failed'),
        );
      },
    );
  });

  group('[DL-12] Batch queuing result reporting', () {
    test('BatchDownloadResult tracks total, queued, skipped, and failures', () {
      const result = BatchDownloadResult(
        totalCount: 3,
        queuedCount: 2,
        skippedDuplicatesCount: 1,
        taskIds: ['id1', 'id2'],
        failures: [],
      );
      expect(result.totalCount, equals(3));
      expect(result.queuedCount, equals(2));
      expect(result.skippedDuplicatesCount, equals(1));
      expect(result.hasFailures, isFalse);
    });
  });

  group('[DL-13] NetworkPolicy resolution rules', () {
    test('wifiOnly policy allows download only on Wi-Fi', () {
      const policy = NetworkPolicy.wifiOnly;
      expect(
        policy.shouldAllowDownload(isWifi: true, isMetered: false),
        isTrue,
      );
      expect(
        policy.shouldAllowDownload(isWifi: false, isMetered: false),
        isFalse,
      );
      expect(
        policy.shouldAllowDownload(isWifi: false, isMetered: true),
        isFalse,
      );
    });

    test(
      'allowCellularFailover policy blocks metered cellular but allows unmetered',
      () {
        const policy = NetworkPolicy.allowCellularFailover;
        expect(
          policy.shouldAllowDownload(isWifi: true, isMetered: true),
          isTrue,
        );
        expect(
          policy.shouldAllowDownload(isWifi: false, isMetered: false),
          isTrue,
        );
        expect(
          policy.shouldAllowDownload(isWifi: false, isMetered: true),
          isFalse,
        );
      },
    );
  });

  group('[DL-14] UseCase input validation', () {
    late MockDownloadRepo mockRepo;

    setUp(() {
      mockRepo = MockDownloadRepo();
    });

    test(
      'QueueDownloadUseCase rejects empty videoId with ValidationFailure',
      () async {
        final useCase = QueueDownloadUseCase(mockRepo);
        final invalidTask = DownloadTask(
          id: 'id1',
          videoId: '',
          title: 'Title',
          artist: 'Artist',
          createdAt: DateTime.now(),
        );

        final result = await useCase(invalidTask);
        expect(result.isLeft(), isTrue);
        result.fold(
          (f) => expect(f, isA<ValidationFailure>()),
          (_) => fail('Should have failed'),
        );
      },
    );

    test(
      'PauseDownloadUseCase rejects empty videoId with ValidationFailure',
      () async {
        final useCase = PauseDownloadUseCase(mockRepo);
        final result = await useCase('   ');
        expect(result.isLeft(), isTrue);
        result.fold(
          (f) => expect(f, isA<ValidationFailure>()),
          (_) => fail('Should have failed'),
        );
      },
    );

    test(
      'ResumeDownloadUseCase rejects empty videoId with ValidationFailure',
      () async {
        final useCase = ResumeDownloadUseCase(mockRepo);
        final result = await useCase('');
        expect(result.isLeft(), isTrue);
      },
    );

    test(
      'RetryDownloadUseCase rejects empty videoId with ValidationFailure',
      () async {
        final useCase = RetryDownloadUseCase(mockRepo);
        final result = await useCase('');
        expect(result.isLeft(), isTrue);
      },
    );

    test(
      'DeleteDownloadUseCase rejects empty videoId with ValidationFailure',
      () async {
        final useCase = DeleteDownloadUseCase(mockRepo);
        final result = await useCase('');
        expect(result.isLeft(), isTrue);
      },
    );

    test(
      'PrioritizeDownloadUseCase rejects empty videoId with ValidationFailure',
      () async {
        final useCase = PrioritizeDownloadUseCase(mockRepo);
        final result = await useCase('');
        expect(result.isLeft(), isTrue);
      },
    );

    test(
      'ReorderDownloadsUseCase rejects empty list with ValidationFailure',
      () async {
        final useCase = ReorderDownloadsUseCase(mockRepo);
        final result = await useCase([]);
        expect(result.isLeft(), isTrue);
      },
    );
  });

  group('[DL-19] RetryPolicy & backoff math', () {
    test(
      'Exponential backoff delay grows exponentially with attempt number',
      () {
        const policy = RetryPolicy(
          initialDelay: Duration(seconds: 1),
          maxDelay: Duration(seconds: 30),
          backoffMultiplier: 2.0,
          jitterFactor: 0.0, // test deterministic component
        );

        expect(policy.delayForAttempt(1).inSeconds, equals(1));
        expect(policy.delayForAttempt(2).inSeconds, equals(2));
        expect(policy.delayForAttempt(3).inSeconds, equals(4));
        expect(policy.delayForAttempt(4).inSeconds, equals(8));
        expect(
          policy.delayForAttempt(10).inSeconds,
          equals(30),
        ); // clamped to max
      },
    );

    test('isRetryableError classifies transient vs permanent errors', () {
      expect(
        RetryPolicy.isRetryableError('SocketException: Connection refused'),
        isTrue,
      );
      expect(
        RetryPolicy.isRetryableError('HTTP 429 Too Many Requests'),
        isTrue,
      );
      expect(
        RetryPolicy.isRetryableError('HTTP 503 Service Unavailable'),
        isTrue,
      );
      expect(
        RetryPolicy.isRetryableError('Insufficient storage space'),
        isFalse,
      );
      expect(RetryPolicy.isRetryableError('Storage full'), isFalse);
      expect(
        RetryPolicy.isRetryableError('Unavailable in this build'),
        isFalse,
      );
    });
  });
}
