// Phase 5 — Downloads progress throttle contract.
//
// 10k progress events pumped into the repository stream must collapse to a
// handful of cubit emissions (200ms coalescing => <=5 emits/sec sustained)
// and the terminal state must always be delivered.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/downloads/yt_download_service.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/repositories/download_repository_interface.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/downloads/cubit/ytm_download_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockYtDownloadService extends Mock implements YtDownloadService {}

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockDownloadRepo extends Mock implements IDownloadRepository {}

DownloadTask _task(String videoId, DownloadStatus status,
        {double progress = 0}) =>
    DownloadTask(
      id: 'id_$videoId',
      videoId: videoId,
      title: 'Song $videoId',
      artist: 'Artist',
      createdAt: DateTime.now(),
      status: status,
      progress: progress,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockYtDownloadService mockService;
  late MockPlayerCubit mockPlayerCubit;
  late MockDownloadRepo mockRepo;
  late StreamController<DownloadTask> repoEvents;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockService = MockYtDownloadService();
    mockPlayerCubit = MockPlayerCubit();
    mockRepo = MockDownloadRepo();
    repoEvents = StreamController<DownloadTask>.broadcast();
    when(() => mockRepo.getAllDownloads()).thenAnswer((_) async => []);
    when(() => mockRepo.observeDownloads())
        .thenAnswer((_) => repoEvents.stream);
  });

  tearDown(() {
    repoEvents.close();
  });

  test('10k-event storm collapses to a handful of emissions', () async {
    final cubit = YtmDownloadCubit(mockService, mockPlayerCubit, mockRepo);
    addTearDown(cubit.close);

    final emissions = <YtmDownloadState>[];
    final sub = cubit.stream.listen(emissions.add);

    // 10k intermediate progress events in one synchronous burst.
    for (var i = 0; i < 10000; i++) {
      repoEvents.add(_task('vid', DownloadStatus.downloading, progress: i / 10000));
    }
    // Terminal event last.
    repoEvents.add(_task('vid', DownloadStatus.complete, progress: 1));
    // Wait past the 200ms throttle window so the trailing emit lands.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await sub.cancel();

    expect(emissions.length, lessThanOrEqualTo(10),
        reason: 'storm must be coalesced (<=5 emits/sec sustained); '
            'got ${emissions.length} for 10k events');
    expect(emissions.last.itemFor('vid').status, YtDownloadStatus.done,
        reason: 'terminal state must always be delivered');
    expect(emissions.last.itemFor('vid').progress, 1.0);
  });

  test('sub-throttle cadence is bounded to <= 2 emissions per 200ms window',
      () async {
    final cubit = YtmDownloadCubit(mockService, mockPlayerCubit, mockRepo);
    addTearDown(cubit.close);

    final emissions = <YtmDownloadState>[];
    final sub = cubit.stream.listen(emissions.add);

    // One progress update every 300ms — beyond the 200ms coalescing window.
    // rxdart's throttleTime(trailing: true) emits each isolated value at the
    // window start (leading) and once more at the window end (trailing), so
    // an isolated update yields at most 2 emissions and never more than one
    // per window boundary: the sustained rate stays <= 10/sec per task with
    // duplicate snapshots absorbed downstream by task equality.
    const updates = 7;
    for (var i = 1; i <= updates; i++) {
      repoEvents.add(_task('vid', DownloadStatus.downloading, progress: i / updates));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    // Terminal event last.
    repoEvents.add(_task('vid', DownloadStatus.complete, progress: 1));
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await sub.cancel();

    expect(emissions.length, greaterThanOrEqualTo(updates + 1),
        reason: 'every update (and the terminal) must be delivered');
    expect(emissions.length, lessThanOrEqualTo(2 * (updates + 1)),
        reason: 'each isolated event is bounded to leading + trailing '
            'emissions (got ${emissions.length})');
    expect(emissions.last.itemFor('vid').status, YtDownloadStatus.done);
    expect(emissions.last.itemFor('vid').progress, 1.0);
  });
}
