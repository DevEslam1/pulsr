// Regression test: YtmDownloadCubit._set must never downgrade a terminal
// status (done/failed/canceled) back to queued/running. This is the guard
// against "stuck on downloading forever" desyncs between optimistic writes
// and the throttled repository stream.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/downloads/yt_download_service.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_download_cubit.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/repositories/download_repository_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockYtDownloadService extends Mock implements YtDownloadService {}

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockDownloadRepo extends Mock implements IDownloadRepository {}

DownloadTask _task(String videoId, DownloadStatus status) => DownloadTask(
      id: 'id_$videoId',
      videoId: videoId,
      title: 'Song',
      artist: 'Artist',
      createdAt: DateTime.now(),
      status: status,
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

  group('YtmDownloadCubit terminal-state guard', () {
    test('canceled item is not downgraded by a stale running event', () async {
      final cubit = YtmDownloadCubit(mockService, mockPlayerCubit, mockRepo);
      addTearDown(cubit.close);
      cubit.cancelDownload('vid_1');
      expect(cubit.state.itemFor('vid_1').status, YtDownloadStatus.canceled);

      repoEvents.add(_task('vid_1', DownloadStatus.downloading));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(cubit.state.itemFor('vid_1').status, YtDownloadStatus.canceled,
          reason: 'terminal canceled must not be downgraded to running');
    });

    test('completed item is not downgraded by a stale queued event', () async {
      final cubit = YtmDownloadCubit(mockService, mockPlayerCubit, mockRepo);
      addTearDown(cubit.close);
      repoEvents.add(_task('vid_1', DownloadStatus.complete));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(cubit.state.itemFor('vid_1').status, YtDownloadStatus.done);

      repoEvents.add(_task('vid_1', DownloadStatus.queued));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(cubit.state.itemFor('vid_1').status, YtDownloadStatus.done,
          reason: 'terminal done must not be downgraded to queued');
    });

    test('non-terminal items still update normally (no over-guard)', () async {
      final cubit = YtmDownloadCubit(mockService, mockPlayerCubit, mockRepo);
      addTearDown(cubit.close);
      repoEvents.add(_task('vid_1', DownloadStatus.queued));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(cubit.state.itemFor('vid_1').status, YtDownloadStatus.queued);

      repoEvents.add(_task('vid_1', DownloadStatus.downloading));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(cubit.state.itemFor('vid_1').status, YtDownloadStatus.running,
          reason: 'normal progress flow must keep working');
    });
  });
}
