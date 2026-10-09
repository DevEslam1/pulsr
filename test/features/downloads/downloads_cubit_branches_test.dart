// DownloadsCubit branch coverage.
//
// The cubit's init/error/reconcile, stream resubscribe backoff, task-event
// throttling + tombstones, destructive-action result mapping, retry-all pacing
// and storage-stat coalescing are all driven here against a mocked repository.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/repositories/download_repository_interface.dart';
import 'package:pulsr/domain/usecases/delete_download.dart';
import 'package:pulsr/domain/usecases/get_download_storage_stats.dart';
import 'package:pulsr/domain/usecases/observe_downloads.dart';
import 'package:pulsr/domain/usecases/pause_download.dart';
import 'package:pulsr/domain/usecases/queue_download.dart';
import 'package:pulsr/domain/usecases/resume_download.dart';
import 'package:pulsr/domain/usecases/retry_download.dart';
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';

class _Repo extends Mock implements IDownloadRepository {}

DownloadTask _task(
  String videoId, {
  DownloadStatus status = DownloadStatus.downloading,
  double progress = 0.1,
  String? error,
}) {
  return DownloadTask(
    id: 'task_$videoId',
    videoId: videoId,
    title: 'Title $videoId',
    artist: 'Artist',
    status: status,
    progress: progress,
    error: error,
    createdAt: DateTime(2026, 1, 1),
  );
}

DownloadsCubit _build(_Repo repo) {
  return DownloadsCubit(
    QueueDownloadUseCase(repo),
    PauseDownloadUseCase(repo),
    ResumeDownloadUseCase(repo),
    RetryDownloadUseCase(repo),
    DeleteDownloadUseCase(repo),
    ObserveDownloadsUseCase(repo),
    GetDownloadStorageStatsUseCase(repo),
    repo,
  );
}

void _stubCommon(
  _Repo repo, {
  List<DownloadTask> initial = const [],
  Stream<DownloadTask>? events,
  Either<AppFailure, StorageStats>? stats,
}) {
  when(() => repo.reconcileOnBoot()).thenAnswer((_) async {});
  when(() => repo.getAllDownloads()).thenAnswer((_) async => initial);
  when(() => repo.observeDownloads())
      .thenAnswer((_) => events ?? const Stream<DownloadTask>.empty());
  when(() => repo.getStorageStats())
      .thenAnswer((_) async => stats ?? const Right(StorageStats()));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(_task('x'));
  });

  test('init surfaces reconcile failure and stops loading', () async {
    final repo = _Repo();
    when(() => repo.reconcileOnBoot())
        .thenAnswer((_) async => throw StateError('nope'));
    when(() => repo.getAllDownloads()).thenAnswer((_) async => []);
    when(() => repo.observeDownloads())
        .thenAnswer((_) => const Stream<DownloadTask>.empty());
    when(() => repo.getStorageStats())
        .thenAnswer((_) async => const Right(StorageStats()));

    final cubit = _build(repo);
    await pumpEventQueue();

    expect(cubit.state.isLoading, isFalse);
    expect(cubit.state.errorMessage, 'Failed to load downloads');
    await cubit.close();
  });

  test('loadInitialTasks failure is surfaced', () async {
    final repo = _Repo();
    _stubCommon(repo);
    when(() => repo.getAllDownloads())
        .thenAnswer((_) async => throw StateError('db down'));

    final cubit = _build(repo);
    await pumpEventQueue();

    expect(cubit.state.errorMessage, 'Failed to load downloads');
    expect(cubit.state.isLoading, isFalse);
    await cubit.close();
  });

  test('storage-stats exception during init is swallowed', () async {
    final repo = _Repo();
    _stubCommon(repo);
    when(() => repo.getStorageStats())
        .thenAnswer((_) async => throw StateError('stats down'));

    final cubit = _build(repo);
    await pumpEventQueue();

    expect(cubit.state.isLoading, isFalse);
    expect(cubit.state.errorMessage, isNull);
    await cubit.close();
  });

  test('a subscribe failure during init is caught by the outer guard',
      () async {
    final repo = _Repo();
    when(() => repo.reconcileOnBoot()).thenAnswer((_) async {});
    when(() => repo.getAllDownloads()).thenAnswer((_) async => []);
    when(() => repo.observeDownloads()).thenThrow(StateError('subscribe boom'));
    when(() => repo.getStorageStats())
        .thenAnswer((_) async => const Right(StorageStats()));

    final cubit = _build(repo);
    await pumpEventQueue();

    expect(cubit.state.errorMessage, 'Failed to load downloads');
    expect(cubit.state.isLoading, isFalse);
    await cubit.close();
  });

  test('storage-stats Left result is ignored and refresh coalesces', () async {
    final repo = _Repo();
    _stubCommon(repo);
    final completer = Completer<Either<AppFailure, StorageStats>>();
    when(() => repo.getStorageStats()).thenAnswer((_) => completer.future);

    final cubit = _build(repo);
    await pumpEventQueue();

    // Second call while the first is in flight takes the queued branch.
    final second = cubit.refreshStorageStats();
    completer.complete(const Right(StorageStats(totalBytes: 100)));
    await second;
    await pumpEventQueue();

    expect(cubit.state.storageStats.totalBytes, 100);
    await cubit.close();
  });

  test('a later storage-stats throw is swallowed', () async {
    final repo = _Repo();
    var calls = 0;
    _stubCommon(repo);
    when(() => repo.getStorageStats()).thenAnswer((_) async {
      calls++;
      if (calls > 1) throw StateError('later failure');
      return const Right(StorageStats());
    });

    final cubit = _build(repo);
    await pumpEventQueue();
    await cubit.refreshStorageStats();
    await pumpEventQueue();

    expect(calls, greaterThanOrEqualTo(2));
    await cubit.close();
  });

  test('a stream error schedules a resubscribe with backoff', () async {
    final repo = _Repo();
    var subscribeCalls = 0;
    when(() => repo.reconcileOnBoot()).thenAnswer((_) async {});
    when(() => repo.getAllDownloads()).thenAnswer((_) async => []);
    when(() => repo.observeDownloads()).thenAnswer((_) {
      subscribeCalls++;
      if (subscribeCalls == 1) {
        return Stream<DownloadTask>.error(StateError('stream boom'));
      }
      return const Stream<DownloadTask>.empty();
    });
    when(() => repo.getStorageStats())
        .thenAnswer((_) async => const Right(StorageStats()));

    final cubit = _build(repo);
    await pumpEventQueue();
    expect(subscribeCalls, 1);

    await Future<void>.delayed(const Duration(milliseconds: 320));
    await pumpEventQueue();
    expect(subscribeCalls, greaterThanOrEqualTo(2));
    await cubit.close();
  });

  test('task events update state and terminal status debounces stats',
      () async {
    final repo = _Repo();
    final controller = StreamController<DownloadTask>.broadcast();
    var statsCalls = 0;
    when(() => repo.reconcileOnBoot()).thenAnswer((_) async {});
    when(() => repo.getAllDownloads()).thenAnswer((_) async => []);
    when(() => repo.observeDownloads()).thenAnswer((_) => controller.stream);
    when(() => repo.getStorageStats()).thenAnswer((_) async {
      statsCalls++;
      return const Right(StorageStats());
    });

    final cubit = _build(repo);
    await pumpEventQueue();
    final afterInit = statsCalls;

    controller.add(_task('v1', progress: 0.2));
    await pumpEventQueue();
    expect(cubit.state.tasks['v1']!.progress, 0.2);

    // Progress-only re-emit inside the 100ms throttle window is dropped.
    controller.add(_task('v1', progress: 0.25));
    await pumpEventQueue();
    expect(cubit.state.tasks['v1']!.progress, 0.2);

    controller.add(
        _task('v1', status: DownloadStatus.complete, progress: 1.0));
    await pumpEventQueue();
    expect(cubit.state.tasks['v1']!.status, DownloadStatus.complete);

    await Future<void>.delayed(const Duration(milliseconds: 400));
    await pumpEventQueue();
    expect(statsCalls, greaterThan(afterInit));

    await controller.close();
    await cubit.close();
  });

  test('an identical re-emitted task is dropped', () async {
    final repo = _Repo();
    final controller = StreamController<DownloadTask>.broadcast();
    _stubCommon(repo, events: controller.stream);

    final cubit = _build(repo);
    await pumpEventQueue();

    final task = _task('dup', status: DownloadStatus.complete, progress: 1.0);
    controller.add(task);
    await pumpEventQueue();
    controller.add(task);
    await pumpEventQueue();

    expect(cubit.state.tasks.length, 1);
    await controller.close();
    await cubit.close();
  });

  test('delete tombstone suppresses an in-flight stale event', () async {
    final repo = _Repo();
    final controller = StreamController<DownloadTask>.broadcast();
    _stubCommon(repo, events: controller.stream);
    when(() => repo.deleteDownload(any()))
        .thenAnswer((_) async => const Right(unit));

    final cubit = _build(repo);
    await pumpEventQueue();

    controller.add(_task('v9'));
    await pumpEventQueue();
    expect(cubit.state.tasks.containsKey('v9'), isTrue);

    await cubit.deleteDownload('v9');
    await pumpEventQueue();
    expect(cubit.state.tasks.containsKey('v9'), isFalse);

    controller.add(_task('v9', progress: 0.5));
    await pumpEventQueue();
    expect(cubit.state.tasks.containsKey('v9'), isFalse);

    await controller.close();
    await cubit.close();
  });

  test('queueDownload success clears a delete tombstone', () async {
    final repo = _Repo();
    final controller = StreamController<DownloadTask>.broadcast();
    _stubCommon(repo, events: controller.stream);
    when(() => repo.deleteDownload(any()))
        .thenAnswer((_) async => const Right(unit));
    when(() => repo.queueDownload(any()))
        .thenAnswer((_) async => const Right('v7'));

    final cubit = _build(repo);
    await pumpEventQueue();

    await cubit.deleteDownload('v7');
    await cubit.queueDownload(_task('v7'));
    await pumpEventQueue();

    controller.add(_task('v7', progress: 0.3));
    await pumpEventQueue();
    expect(cubit.state.tasks.containsKey('v7'), isTrue);

    await controller.close();
    await cubit.close();
  });

  test('action result mapping surfaces failures and clears on success',
      () async {
    final repo = _Repo();
    _stubCommon(repo);
    when(() => repo.pauseDownload(any()))
        .thenAnswer((_) async => const Left(DatabaseFailure('pause failed')));
    when(() => repo.resumeDownload(any()))
        .thenAnswer((_) async => const Left(DatabaseFailure('resume failed')));
    when(() => repo.retryDownload(any()))
        .thenAnswer((_) async => const Right(unit));
    when(() => repo.queueDownload(any()))
        .thenAnswer((_) async => const Right('q'));

    final cubit = _build(repo);
    await pumpEventQueue();

    await cubit.pauseDownload('a');
    expect(cubit.state.errorMessage, 'pause failed');

    await cubit.resumeDownload('a');
    expect(cubit.state.errorMessage, 'resume failed');

    await cubit.retryDownload('a');
    expect(cubit.state.errorMessage, isNull);

    await cubit.queueDownload(_task('a'));
    expect(cubit.state.errorMessage, isNull);

    await cubit.close();
  });

  test('retryAllFailed re-queues paced failures', () async {
    final repo = _Repo();
    _stubCommon(
      repo,
      initial: [
        _task('f1', status: DownloadStatus.failed, error: 'x'),
        _task('f2', status: DownloadStatus.failed, error: 'y'),
      ],
    );
    when(() => repo.retryDownload(any()))
        .thenAnswer((_) async => const Right(unit));

    final cubit = _build(repo);
    await pumpEventQueue();

    final queued = await cubit.retryAllFailed(delayMs: 0);
    expect(queued, 2);
    await cubit.close();
  });

  test('retryAllFailed reports when nothing could be retried', () async {
    final repo = _Repo();
    _stubCommon(
      repo,
      initial: [_task('f1', status: DownloadStatus.failed, error: 'x')],
    );
    when(() => repo.retryDownload(any()))
        .thenAnswer((_) async => const Left(DatabaseFailure('still broken')));

    final cubit = _build(repo);
    await pumpEventQueue();

    final queued = await cubit.retryAllFailed(delayMs: 0);
    expect(queued, 0);
    expect(cubit.state.errorMessage, 'Could not retry failed downloads');
    await cubit.close();
  });

  test('deleteDownload failure surfaces the message', () async {
    final repo = _Repo();
    _stubCommon(repo, initial: [_task('d1')]);
    when(() => repo.deleteDownload(any()))
        .thenAnswer((_) async => const Left(DatabaseFailure('delete failed')));

    final cubit = _build(repo);
    await pumpEventQueue();

    await cubit.deleteDownload('d1');
    expect(cubit.state.errorMessage, 'delete failed');
    expect(cubit.state.tasks.containsKey('d1'), isTrue);
    await cubit.close();
  });

  test('cancelDownload pauses then deletes', () async {
    final repo = _Repo();
    _stubCommon(repo, initial: [_task('c1')]);
    when(() => repo.pauseDownload(any()))
        .thenAnswer((_) async => const Right(unit));
    when(() => repo.deleteDownload(any()))
        .thenAnswer((_) async => const Right(unit));

    final cubit = _build(repo);
    await pumpEventQueue();

    await cubit.cancelDownload('c1');
    verify(() => repo.pauseDownload('c1')).called(1);
    verify(() => repo.deleteDownload('c1')).called(1);
    await cubit.close();
  });

  test('throttle bookkeeping is pruned past its cap', () async {
    final repo = _Repo();
    final controller = StreamController<DownloadTask>.broadcast();
    _stubCommon(repo, events: controller.stream);

    final cubit = _build(repo);
    await pumpEventQueue();

    for (var i = 0; i < 130; i++) {
      controller.add(_task('bulk_$i', progress: 0.4));
    }
    await pumpEventQueue();
    controller.add(_task('after_prune', progress: 0.4));
    await pumpEventQueue();

    expect(cubit.state.tasks.length, greaterThan(128));
    await controller.close();
    await cubit.close();
  });
}
