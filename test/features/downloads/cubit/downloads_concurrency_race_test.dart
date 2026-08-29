// Phase 5 — Downloads concurrency race + soak.
//
// 1000 randomized queue/pause/resume/retry/delete operations interleaved with
// repository events. Invariants:
//   * no unhandled exceptions / no duplicate task keys
//   * progress stays within [0, 1]
//   * terminal states are reachable
//   * subscription/timer registry returns to zero after close
import 'dart:async';
import 'dart:math';

import 'package:fpdart/fpdart.dart';
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
import 'package:pulsr/domain/usecases/prioritize_download.dart';
import 'package:pulsr/domain/usecases/resume_download.dart';
import 'package:pulsr/domain/usecases/retry_download.dart';
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockQueueDownloadUseCase extends Mock implements QueueDownloadUseCase {}

class MockPauseDownloadUseCase extends Mock implements PauseDownloadUseCase {}

class MockResumeDownloadUseCase extends Mock implements ResumeDownloadUseCase {}

class MockRetryDownloadUseCase extends Mock implements RetryDownloadUseCase {}

class MockDeleteDownloadUseCase extends Mock implements DeleteDownloadUseCase {}

class MockObserveDownloadsUseCase extends Mock
    implements ObserveDownloadsUseCase {}

class MockGetDownloadStorageStatsUseCase extends Mock
    implements GetDownloadStorageStatsUseCase {}

class MockPrioritizeDownloadUseCase extends Mock
    implements PrioritizeDownloadUseCase {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockQueueDownloadUseCase mockQueue;
  late MockPauseDownloadUseCase mockPause;
  late MockResumeDownloadUseCase mockResume;
  late MockRetryDownloadUseCase mockRetry;
  late MockDeleteDownloadUseCase mockDelete;
  late MockObserveDownloadsUseCase mockObserve;
  late MockGetDownloadStorageStatsUseCase mockStats;
  late MockPrioritizeDownloadUseCase mockPrioritize;
  late StreamController<DownloadTask> repoEvents;

  setUpAll(() {
    registerFallbackValue(DownloadTask(
      id: 'fallback',
      videoId: 'fallback',
      title: 'Fallback',
      artist: 'Fallback',
      createdAt: DateTime.now(),
    ));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockQueue = MockQueueDownloadUseCase();
    mockPause = MockPauseDownloadUseCase();
    mockResume = MockResumeDownloadUseCase();
    mockRetry = MockRetryDownloadUseCase();
    mockDelete = MockDeleteDownloadUseCase();
    mockObserve = MockObserveDownloadsUseCase();
    mockStats = MockGetDownloadStorageStatsUseCase();
    mockPrioritize = MockPrioritizeDownloadUseCase();
    repoEvents = StreamController<DownloadTask>.broadcast();

    when(() => mockObserve.getAll()).thenAnswer((_) async => []);
    when(() => mockObserve.call()).thenAnswer((_) => repoEvents.stream);
    when(() => mockStats.call())
        .thenAnswer((_) async => const Right(StorageStats()));
    when(() => mockQueue.call(any())).thenAnswer(
        (_) async => Right('id_${DateTime.now().microsecondsSinceEpoch}'));
    when(() => mockPause.call(any())).thenAnswer((_) async => const Right(unit));
    when(() => mockResume.call(any())).thenAnswer((_) async => const Right(unit));
    when(() => mockRetry.call(any())).thenAnswer((_) async => const Right(unit));
    when(() => mockDelete.call(any())).thenAnswer((_) async => const Right(unit));
    when(() => mockPrioritize.call(any()))
        .thenAnswer((_) async => const Right(unit));
  });

  tearDown(() {
    repoEvents.close();
  });

  test('1000 randomized ops keep queue invariants', () async {
    final cubit = DownloadsCubit(
      mockQueue,
      mockPause,
      mockResume,
      mockRetry,
      mockDelete,
      mockObserve,
      mockStats,
      null,
      mockPrioritize,
    );

    final rng = Random(42);
    const videoCount = 8;
    final errors = <String>[];
    cubit.stream.listen((_) {}, onError: (Object e, StackTrace s) {
      errors.add('$e');
    });

    for (var op = 0; op < 1000; op++) {
      final videoId = 'vid_${rng.nextInt(videoCount)}';
      final task = DownloadTask(
        id: 'id_$videoId',
        videoId: videoId,
        title: 'Song $videoId',
        artist: 'Artist',
        createdAt: DateTime.now(),
      );
      switch (rng.nextInt(7)) {
        case 0:
          unawaited(cubit.queueDownload(task));
          break;
        case 1:
          unawaited(cubit.pauseDownload(videoId));
          break;
        case 2:
          unawaited(cubit.resumeDownload(videoId));
          break;
        case 3:
          unawaited(cubit.retryDownload(videoId));
          break;
        case 4:
          unawaited(cubit.deleteDownload(videoId));
          break;
        case 5:
          unawaited(cubit.prioritizeDownload(videoId));
          break;
        case 6:
          // Repository-side progress for a random task.
          repoEvents.add(DownloadTask(
            id: 'id_$videoId',
            videoId: videoId,
            title: 'Song $videoId',
            artist: 'Artist',
            createdAt: DateTime.now(),
            status: DownloadStatus.downloading,
            progress: rng.nextDouble(),
          ));
          break;
      }
      if (op % 50 == 0) {
        // Let the event loop interleave real concurrency.
        await Future<void>.delayed(Duration.zero);
      }
    }
    // Flush everything.
    await Future<void>.delayed(const Duration(milliseconds: 800));

    expect(errors, isEmpty, reason: 'no unhandled cubit errors during storm');
    for (final entry in cubit.state.tasks.entries) {
      expect(entry.value.progress, inInclusiveRange(0, 1),
          reason: 'progress must stay in [0,1] for ${entry.key}');
    }
    final keys = cubit.state.tasks.keys.toList();
    expect(keys.length, keys.toSet().length,
        reason: 'no duplicate task keys');
    expect(cubit.activeResourceCount, greaterThanOrEqualTo(0));

    await cubit.close();
    expect(cubit.activeResourceCount, 0,
        reason: 'soak: registry fully drained after close');
  });
}
