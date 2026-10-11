// DownloadsCubit.retryDownloads: paced re-queueing for a bulk selection (it
// must never fire every request at once, which tripped YouTube's 429/bot
// throttling), and the honest counts surfaced to the screen.
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
  DownloadStatus status = DownloadStatus.failed,
}) =>
    DownloadTask(
      id: 'task_$videoId',
      videoId: videoId,
      title: 'Title $videoId',
      artist: 'Artist',
      status: status,
      error: 'boom',
      createdAt: DateTime(2026, 1, 1),
    );

DownloadsCubit _build(_Repo repo) => DownloadsCubit(
      QueueDownloadUseCase(repo),
      PauseDownloadUseCase(repo),
      ResumeDownloadUseCase(repo),
      RetryDownloadUseCase(repo),
      DeleteDownloadUseCase(repo),
      ObserveDownloadsUseCase(repo),
      GetDownloadStorageStatsUseCase(repo),
      repo,
    );

void _stubCommon(_Repo repo, {List<DownloadTask> initial = const []}) {
  when(() => repo.reconcileOnBoot()).thenAnswer((_) async {});
  when(() => repo.getAllDownloads()).thenAnswer((_) async => initial);
  when(() => repo.observeDownloads())
      .thenAnswer((_) => const Stream<DownloadTask>.empty());
  when(() => repo.getStorageStats())
      .thenAnswer((_) async => const Right(StorageStats()));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(_task('fallback'));
  });

  test('retryDownloads re-queues only the given ids, paced', () async {
    final repo = _Repo();
    _stubCommon(repo, initial: [
      _task('f1'),
      _task('f2'),
      _task('f3'),
      _task('d1', status: DownloadStatus.downloading),
    ]);
    when(() => repo.retryDownload(any()))
        .thenAnswer((_) async => const Right(unit));

    final cubit = _build(repo);
    await pumpEventQueue();

    final stopwatch = Stopwatch()..start();
    final queued = await cubit.retryDownloads(['f1', 'f2'], delayMs: 30);
    stopwatch.stop();

    expect(queued, 2);
    verify(() => repo.retryDownload('f1')).called(1);
    verify(() => repo.retryDownload('f2')).called(1);
    verifyNever(() => repo.retryDownload('f3'));
    verifyNever(() => repo.retryDownload('d1'));
    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(25),
        reason: 'two requests must be spaced by the pacing delay');
    await cubit.close();
  });

  test('retryDownloads reports when nothing could be re-queued', () async {
    final repo = _Repo();
    _stubCommon(repo, initial: [_task('f1')]);
    when(() => repo.retryDownload(any()))
        .thenAnswer((_) async => const Left(DatabaseFailure('still broken')));

    final cubit = _build(repo);
    await pumpEventQueue();

    final queued = await cubit.retryDownloads(['f1'], delayMs: 0);
    expect(queued, 0);
    expect(cubit.state.errorMessage, 'Could not retry failed downloads');
    await cubit.close();
  });

  test(
      'retryAllFailed still re-queues every failed task through the paced path',
      () async {
    final repo = _Repo();
    _stubCommon(repo, initial: [_task('f1'), _task('f2')]);
    when(() => repo.retryDownload(any()))
        .thenAnswer((_) async => const Right(unit));

    final cubit = _build(repo);
    await pumpEventQueue();

    expect(await cubit.retryAllFailed(delayMs: 0), 2);
    verify(() => repo.retryDownload('f1')).called(1);
    verify(() => repo.retryDownload('f2')).called(1);
    await cubit.close();
  });
}
