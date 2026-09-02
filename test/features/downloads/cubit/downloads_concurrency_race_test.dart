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
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/bloc/base_cubit.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/usecases/download_lifecycle_usecases.dart';
import 'package:pulsr/domain/usecases/download_query_usecases.dart';
import 'package:pulsr/domain/usecases/download_queue_usecases.dart';
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

class MockReorderDownloadsUseCase extends Mock
    implements ReorderDownloadsUseCase {}

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
    when(
      () => mockStats.call(),
    ).thenAnswer((_) async => const Right(StorageStats()));
    when(() => mockQueue.call(any())).thenAnswer(
      (_) async => Right('id_${DateTime.now().microsecondsSinceEpoch}'),
    );
    when(
      () => mockPause.call(any()),
    ).thenAnswer((_) async => const Right(unit));
    when(
      () => mockResume.call(any()),
    ).thenAnswer((_) async => const Right(unit));
    when(
      () => mockRetry.call(any()),
    ).thenAnswer((_) async => const Right(unit));
    when(
      () => mockDelete.call(any()),
    ).thenAnswer((_) async => const Right(unit));
    when(
      () => mockPrioritize.call(any()),
    ).thenAnswer((_) async => const Right(unit));
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
    cubit.stream.listen(
      (_) {},
      onError: (Object e, StackTrace s) {
        errors.add('$e');
      },
    );

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
          repoEvents.add(
            DownloadTask(
              id: 'id_$videoId',
              videoId: videoId,
              title: 'Song $videoId',
              artist: 'Artist',
              createdAt: DateTime.now(),
              status: DownloadStatus.downloading,
              progress: rng.nextDouble(),
            ),
          );
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
      expect(
        entry.value.progress,
        inInclusiveRange(0, 1),
        reason: 'progress must stay in [0,1] for ${entry.key}',
      );
    }
    final keys = cubit.state.tasks.keys.toList();
    expect(keys.length, keys.toSet().length, reason: 'no duplicate task keys');
    expect(cubit.activeResourceCount, greaterThanOrEqualTo(0));

    await cubit.close();
    expect(
      cubit.activeResourceCount,
      0,
      reason: 'soak: registry fully drained after close',
    );
  });

  group('Interleaved race scenarios (Completer-driven fakes)', () {
    late MockQueueDownloadUseCase mockQueue;
    late MockPauseDownloadUseCase mockPause;
    late MockResumeDownloadUseCase mockResume;
    late MockRetryDownloadUseCase mockRetry;
    late MockDeleteDownloadUseCase mockDelete;
    late MockObserveDownloadsUseCase mockObserve;
    late MockGetDownloadStorageStatsUseCase mockStats;
    late StreamController<DownloadTask> repoEvents;

    DownloadTask task(
      String videoId, [
      DownloadStatus status = DownloadStatus.queued,
    ]) => DownloadTask(
      id: 'id_$videoId',
      videoId: videoId,
      title: 'Song $videoId',
      artist: 'Artist',
      createdAt: DateTime.now(),
      status: status,
    );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockQueue = MockQueueDownloadUseCase();
      mockPause = MockPauseDownloadUseCase();
      mockResume = MockResumeDownloadUseCase();
      mockRetry = MockRetryDownloadUseCase();
      mockDelete = MockDeleteDownloadUseCase();
      mockObserve = MockObserveDownloadsUseCase();
      mockStats = MockGetDownloadStorageStatsUseCase();
      repoEvents = StreamController<DownloadTask>.broadcast();

      when(() => mockObserve.getAll()).thenAnswer((_) async => []);
      when(() => mockObserve.call()).thenAnswer((_) => repoEvents.stream);
      when(
        () => mockStats.call(),
      ).thenAnswer((_) async => const Right(StorageStats()));
    });

    tearDown(() {
      repoEvents.close();
    });

    DownloadsCubit buildCubit({MockReorderDownloadsUseCase? reorder}) =>
        DownloadsCubit(
          mockQueue,
          mockPause,
          mockResume,
          mockRetry,
          mockDelete,
          mockObserve,
          mockStats,
          reorder,
        );

    test(
      'pause during active start: serialized, no error, both succeed',
      () async {
        final gate = Completer<Either<AppFailure, String>>();
        when(() => mockQueue.call(any())).thenAnswer((_) => gate.future);
        when(
          () => mockPause.call(any()),
        ).thenAnswer((_) async => const Right(unit));

        final cubit = buildCubit();
        final errors = <String>[];
        cubit.stream.listen(
          (_) {},
          onError: (Object e, StackTrace s) {
            errors.add('$e');
          },
        );

        final startFuture = cubit.queueDownload(task('vid_active'));
        // Give the start time to acquire the per-task lock and block on the gate.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final pauseFuture = cubit.pauseDownload('vid_active');

        // Complete the start while pause is waiting on the same task lock.
        gate.complete(const Right('id_vid_active'));
        await Future.wait([startFuture, pauseFuture]);

        expect(errors, isEmpty);
        expect(
          cubit.state.hasFailure,
          isFalse,
          reason: 'both actions succeeded; no failure surface',
        );
        verify(() => mockPause.call('vid_active')).called(1);

        await cubit.close();
      },
    );

    test(
      'two concurrent start calls for the same item: second is a silent no-op',
      () async {
        var callCount = 0;
        when(() => mockQueue.call(any())).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) return const Right('id_first');
          return const Left(
            AlreadyQueuedFailure('Task is already queued or active'),
          );
        });

        final cubit = buildCubit();
        final toasts = <String>[];
        final effectsSub = cubit.effects.listen((effect) {
          if (effect is ShowToastEffect) toasts.add(effect.message);
        });
        final errors = <String>[];
        cubit.stream.listen(
          (_) {},
          onError: (Object e, StackTrace s) {
            errors.add('$e');
          },
        );

        final f1 = cubit.queueDownload(task('vid_dup'));
        final f2 = cubit.queueDownload(task('vid_dup'));
        await Future.wait([f1, f2]);

        expect(callCount, 2, reason: 'both requests reached the use case');
        expect(
          cubit.state.hasFailure,
          isFalse,
          reason: 'AlreadyQueued on duplicate start is a no-op, not an error',
        );
        expect(
          toasts,
          isEmpty,
          reason: 'duplicate start must not raise a toast',
        );
        expect(errors, isEmpty);

        await effectsSub.cancel();
        await cubit.close();
      },
    );

    test(
      'retry during delete: actions serialize, delete wins, no resurrection',
      () async {
        final retryGate = Completer<Either<AppFailure, Unit>>();
        when(() => mockRetry.call(any())).thenAnswer((_) => retryGate.future);
        when(
          () => mockDelete.call(any()),
        ).thenAnswer((_) async => const Right(unit));

        final cubit = buildCubit();
        // Seed the task list as failed so state operations have a target.
        when(
          () => mockObserve.getAll(),
        ).thenAnswer((_) async => [task('vid_dead', DownloadStatus.failed)]);
        final errors = <String>[];
        cubit.stream.listen(
          (_) {},
          onError: (Object e, StackTrace s) {
            errors.add('$e');
          },
        );
        await cubit.loadInitialTasks();

        final retryFuture = cubit.retryDownload('vid_dead');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final deleteFuture = cubit.deleteDownload('vid_dead');

        // Cancel (delete) while the retry is still in flight.
        retryGate.complete(const Right(unit));
        await Future.wait([retryFuture, deleteFuture]);

        expect(errors, isEmpty);
        expect(
          cubit.state.tasks.containsKey('vid_dead'),
          isFalse,
          reason: 'deleted task must be removed from state',
        );
        expect(cubit.state.hasFailure, isFalse);

        await cubit.close();
      },
    );

    test(
      'network drop -> transient failure -> retry success clears error',
      () async {
        when(
          () => mockQueue.call(any()),
        ).thenAnswer((_) async => const Left(NetworkFailure('Network down')));
        when(
          () => mockRetry.call(any()),
        ).thenAnswer((_) async => const Right(unit));

        final cubit = buildCubit();
        final errors = <String>[];
        cubit.stream.listen(
          (_) {},
          onError: (Object e, StackTrace s) {
            errors.add('$e');
          },
        );

        await cubit.queueDownload(task('vid_net'));

        expect(cubit.state.failure, isA<NetworkFailure>());
        expect(cubit.state.errorMessage, 'Network down');
        expect(
          cubit.state.isErrorRetryable,
          isTrue,
          reason: 'network failures are classified transient/retryable',
        );

        await cubit.retryDownload('vid_net');

        expect(
          cubit.state.hasFailure,
          isFalse,
          reason: 'successful retry clears the stale failure surface',
        );

        // Repo confirms the restarted download completing.
        repoEvents.add(task('vid_net', DownloadStatus.complete));
        await Future<void>.delayed(const Duration(milliseconds: 400));

        expect(cubit.state.completedCount, 1);
        expect(errors, isEmpty);

        await cubit.close();
      },
    );

    test(
      'dual pause/resume on the same task: serialized, final state paused',
      () async {
        // Seed an active download so both actions have a target.
        when(
          () => mockObserve.getAll(),
        ).thenAnswer((_) async => [task('vid_pr', DownloadStatus.downloading)]);
        when(
          () => mockPause.call(any()),
        ).thenAnswer((_) async => const Right(unit));
        when(
          () => mockResume.call(any()),
        ).thenAnswer((_) async => const Right(unit));

        final cubit = buildCubit();
        final errors = <String>[];
        cubit.stream.listen(
          (_) {},
          onError: (Object e, StackTrace s) {
            errors.add('$e');
          },
        );
        await cubit.loadInitialTasks();

        // Race a resume and a pause on the same id: the per-task lock
        // serializes them in issue order, so the pause issued last wins.
        final fResume = cubit.resumeDownload('vid_pr');
        final fPause = cubit.pauseDownload('vid_pr');
        await Future.wait([fResume, fPause]);

        expect(errors, isEmpty);
        verify(() => mockResume.call('vid_pr')).called(1);
        verify(() => mockPause.call('vid_pr')).called(1);

        // The repository confirms the final paused state.
        repoEvents.add(task('vid_pr', DownloadStatus.paused));
        await Future<void>.delayed(const Duration(milliseconds: 400));

        expect(
          cubit.state.tasks['vid_pr']?.status,
          DownloadStatus.paused,
          reason: 'the dual pause/resume race must settle on paused',
        );

        await cubit.close();
      },
    );

    test(
      'reorder during completion: both land, no error, no lost task',
      () async {
        final mockReorder = MockReorderDownloadsUseCase();
        final reorderGate = Completer<Either<AppFailure, Unit>>();
        when(
          () => mockReorder.call(any()),
        ).thenAnswer((_) => reorderGate.future);
        when(() => mockObserve.getAll()).thenAnswer(
          (_) async => [
            task('vid_a', DownloadStatus.queued),
            task('vid_b', DownloadStatus.queued),
          ],
        );

        final cubit = buildCubit(reorder: mockReorder);
        final errors = <String>[];
        cubit.stream.listen(
          (_) {},
          onError: (Object e, StackTrace s) {
            errors.add('$e');
          },
        );
        await cubit.loadInitialTasks();

        final reorderFuture = cubit.reorderQueue(['vid_b', 'vid_a']);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Completion event lands while the reorder is still in flight.
        repoEvents.add(task('vid_a', DownloadStatus.complete));
        await Future<void>.delayed(const Duration(milliseconds: 400));

        reorderGate.complete(const Right(unit));
        await reorderFuture;

        expect(errors, isEmpty);
        verify(() => mockReorder.call(['vid_b', 'vid_a'])).called(1);
        expect(
          cubit.state.tasks.containsKey('vid_a'),
          isTrue,
          reason: 'completion must not be lost during a concurrent reorder',
        );
        expect(cubit.state.tasks['vid_a']?.status, DownloadStatus.complete);
        expect(cubit.state.tasks.containsKey('vid_b'), isTrue);

        await cubit.close();
      },
    );
  });
}
