// Phase 5 — Downloads hydration (process-death round-trip).
//
// The download queue must survive process death: tasks persisted by the
// repository are rehydrated by a freshly constructed cubit with equal state.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/downloads/yt_download_service.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/repositories/download_repository_interface.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_download_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockYtDownloadService extends Mock implements YtDownloadService {}

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockDownloadRepo extends Mock implements IDownloadRepository {}

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
    when(() => mockRepo.observeDownloads())
        .thenAnswer((_) => repoEvents.stream);
  });

  tearDown(() {
    repoEvents.close();
  });

  test('cubit recreated after process death restores persisted tasks',
      () async {
    final persisted = [
      DownloadTask(
        id: 'id_vid_1',
        videoId: 'vid_1',
        title: 'Song A',
        artist: 'Artist',
        createdAt: DateTime.now(),
        status: DownloadStatus.complete,
        filePath: '/storage/emulated/0/Music/a.mp3',
      ),
      DownloadTask(
        id: 'id_vid_2',
        videoId: 'vid_2',
        title: 'Song B',
        artist: 'Artist',
        createdAt: DateTime.now(),
        status: DownloadStatus.paused,
      ),
    ];

    // Session 1: repository reports the persisted set (survives process death
    // via SharedPreferences 'pulsr_download_tasks_v2' + reconcileOnBoot).
    when(() => mockRepo.getAllDownloads())
        .thenAnswer((_) async => persisted);
    final first = YtmDownloadCubit(mockService, mockPlayerCubit, mockRepo);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final firstState = first.state;
    await first.close();

    // Session 2: fresh cubit after "process death" reads the same store.
    final second = YtmDownloadCubit(mockService, mockPlayerCubit, mockRepo);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final secondState = second.state;
    await second.close();

    expect(secondState.items.keys, firstState.items.keys,
        reason: 'task ids must round-trip');
    expect(
        secondState.items.values.map((i) => i.status).toSet(),
        firstState.items.values.map((i) => i.status).toSet(),
        reason: 'task statuses must round-trip');
    expect(secondState.itemFor('vid_1').status, YtDownloadStatus.done);
    expect(secondState.itemFor('vid_2').status, YtDownloadStatus.idle,
        reason: 'paused maps to idle projection for the retry UX');
  });
}
