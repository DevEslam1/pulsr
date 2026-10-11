// DownloadsCubit ordering: progress ticks mutate one task, so the cached
// createdAt-descending list is updated in place instead of re-sorted, and a
// newly seen task is inserted at its sorted slot.
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
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';

class _Repo extends Mock implements IDownloadRepository {}

DownloadTask _task(String videoId, int minute, {double progress = 0.0}) =>
    DownloadTask(
      id: 'task_$videoId',
      videoId: videoId,
      title: 'Title $videoId',
      artist: 'Artist',
      status: DownloadStatus.downloading,
      progress: progress,
      createdAt: DateTime(2026, 1, 1, 0, minute),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(_task('fallback', 0));
  });

  test('the cached list stays createdAt-descending across progress ticks',
      () async {
    final repo = _Repo();
    final controller = StreamController<DownloadTask>.broadcast();
    addTearDown(controller.close);
    when(() => repo.reconcileOnBoot()).thenAnswer((_) async {});
    when(() => repo.getAllDownloads()).thenAnswer((_) async => []);
    when(() => repo.observeDownloads()).thenAnswer((_) => controller.stream);
    when(() => repo.getStorageStats())
        .thenAnswer((_) async => const Right(StorageStats()));

    final cubit = DownloadsCubit(
      QueueDownloadUseCase(repo),
      PauseDownloadUseCase(repo),
      ResumeDownloadUseCase(repo),
      RetryDownloadUseCase(repo),
      DeleteDownloadUseCase(repo),
      ObserveDownloadsUseCase(repo),
      GetDownloadStorageStatsUseCase(repo),
      repo,
    );
    await pumpEventQueue();

    controller.add(_task('old', 1, progress: 0.1));
    await pumpEventQueue();
    controller.add(_task('new', 5, progress: 0.1));
    await pumpEventQueue();
    // A task created between the two must land in the middle.
    controller.add(_task('mid', 3, progress: 0.1));
    await pumpEventQueue();

    expect(cubit.state.taskList.map((t) => t.videoId).toList(),
        ['new', 'mid', 'old']);

    // Progress-only tick: same order, same replaced instance. Wait out the
    // cubit's 100ms progress throttle first.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    controller.add(_task('mid', 3, progress: 0.9));
    await pumpEventQueue();
    expect(cubit.state.taskList.map((t) => t.videoId).toList(),
        ['new', 'mid', 'old']);
    expect(cubit.state.tasks['mid']!.progress, 0.9);

    await cubit.close();
  });
}
