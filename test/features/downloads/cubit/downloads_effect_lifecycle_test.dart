// Phase 5 — Downloads effect lifecycle.
//
// Failure toasts are transient UiEffects: consumed exactly once by the UI,
// never re-fired on rebuild, never replayed after close.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockQueueDownloadUseCase mockQueue;
  late MockPauseDownloadUseCase mockPause;
  late MockResumeDownloadUseCase mockResume;
  late MockRetryDownloadUseCase mockRetry;
  late MockDeleteDownloadUseCase mockDelete;
  late MockObserveDownloadsUseCase mockObserve;
  late MockGetDownloadStorageStatsUseCase mockStats;
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

  DownloadsCubit buildCubit() => DownloadsCubit(
    mockQueue,
    mockPause,
    mockResume,
    mockRetry,
    mockDelete,
    mockObserve,
    mockStats,
  );

  test('queue failure emits exactly one ShowToastEffect', () async {
    final cubit = buildCubit();
    addTearDown(cubit.close);

    final effects = <UiEffect>[];
    final sub = cubit.effects.listen(effects.add);

    final task = DownloadTask(
      id: 'id_v1',
      videoId: 'v1',
      title: 'Song',
      artist: 'Artist',
      createdAt: DateTime.now(),
    );
    when(() => mockQueue.call(any())).thenAnswer(
      (_) async => const Left(InsufficientStorageFailure('Storage full')),
    );

    await cubit.queueDownload(task);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(effects.length, 1, reason: 'exactly one effect per failure');
    expect(effects.single, isA<ShowToastEffect>());
    expect((effects.single as ShowToastEffect).message, contains('Storage'));
    await sub.cancel();
  });

  test('effect is not re-fired on rebuild/state churn', () async {
    final cubit = buildCubit();
    addTearDown(cubit.close);

    final effects = <UiEffect>[];
    final sub = cubit.effects.listen(effects.add);

    final task = DownloadTask(
      id: 'id_v1',
      videoId: 'v1',
      title: 'Song',
      artist: 'Artist',
      createdAt: DateTime.now(),
    );
    when(
      () => mockQueue.call(any()),
    ).thenAnswer((_) async => const Left(DownloadFailure('Nope')));

    await cubit.queueDownload(task);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final countAfterFailure = effects.length;
    expect(countAfterFailure, greaterThanOrEqualTo(1));

    // State churn (clearError) must NOT replay the toast.
    cubit.clearError();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      effects.length,
      countAfterFailure,
      reason: 'rebuilds must not re-fire consumed effects',
    );
    await sub.cancel();
  });

  test('effects stream closes with the cubit', () async {
    final cubit = buildCubit();
    final done = Completer<void>();
    final sub = cubit.effects.listen((_) {}, onDone: done.complete);
    addTearDown(sub.cancel);

    await cubit.close();
    await done.future.timeout(const Duration(seconds: 1));
  });
}
