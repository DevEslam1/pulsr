import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/yt_download_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';
import 'package:pulsr/features/downloads/cubit/downloads_state.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_download_cubit.dart';

class MockYtDownloadService extends Mock implements YtDownloadService {}

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockDownloadsCubit extends Mock implements DownloadsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(DownloadTask(
      id: 'fallbackVid1',
      videoId: 'fallbackVid1',
      title: 'Fallback',
      artist: 'Fallback',
      createdAt: DateTime(2026, 1, 1),
    ));
  });

  late MockYtDownloadService mockService;
  late MockPlayerCubit mockPlayerCubit;
  late MockDownloadsCubit mockDownloads;
  late StreamController<DownloadsState> controller;
  late SongsTableData testSong;

  setUp(() {
    mockService = MockYtDownloadService();    mockPlayerCubit = MockPlayerCubit();
    mockDownloads = MockDownloadsCubit();
    controller = StreamController<DownloadsState>.broadcast();
    when(() => mockDownloads.stream).thenAnswer((_) => controller.stream);
    when(() => mockDownloads.queueDownload(any())).thenAnswer((_) async {});
    when(() => mockDownloads.cancelDownload(any())).thenAnswer((_) async {});
    when(() => mockPlayerCubit.swapReconciledSong(any(), any()))
        .thenAnswer((_) async {});

    testSong = const SongsTableData(
      id: -101,
      title: 'Test YTM Song',
      artist: 'Test Artist',
      album: 'Test Album',
      path: 'ytmusic://testVid1',
      source: SongSource.youtube,
      remoteId: 'testVid1',
      durationMs: 210000,
      isFavorite: false,
      playCount: 0,
      lastPositionMs: 0,
      isMissing: false,
      isDownloaded: false,
    );
  });

  tearDown(() async {
    await controller.close();
  });

  YtmDownloadCubit build() =>
      YtmDownloadCubit(mockService, mockPlayerCubit, downloadsCubit: mockDownloads);

  DownloadTask taskWith(DownloadStatus status, {int? localSongId}) =>
      DownloadTask(
        id: 'testVid1',
        videoId: 'testVid1',
        title: 'Test YTM Song',
        artist: 'Test Artist',
        status: status,
        progress: status == DownloadStatus.downloading ? 0.5 : 1.0,
        sourceSongId: -101,
        localSongId: localSongId,
        createdAt: DateTime(2026, 1, 1),
      );

  test('initial state has empty download items', () async {
    final cubit = build();
    expect(cubit.state.items, isEmpty);
    expect(cubit.state.itemFor('nonexistent').status,
        equals(YtDownloadStatus.idle));
    await cubit.close();
  });

  test('download() submits a task to DownloadsCubit and mirrors its states',
      () async {
    final cubit = build();
    final states = <YtmDownloadState>[];
    final sub = cubit.stream.listen(states.add);

    await cubit.download(testSong);

    // Optimistically queued before the repository answers.
    expect(cubit.state.itemFor('testVid1').status, YtDownloadStatus.queued);
    verify(() => mockDownloads.queueDownload(any())).called(1);

    controller.add(DownloadsState(tasks: {
      'testVid1': taskWith(DownloadStatus.downloading),
    }));
    await Future.delayed(Duration.zero);
    expect(cubit.state.itemFor('testVid1').status, YtDownloadStatus.running);
    expect(cubit.state.itemFor('testVid1').progress, 0.5);

    controller.add(DownloadsState(tasks: {
      'testVid1': taskWith(DownloadStatus.complete, localSongId: 501),
    }));
    await Future.delayed(Duration.zero);
    expect(cubit.state.itemFor('testVid1').status, YtDownloadStatus.done);

    // Completion swaps the stale remote row for the local one exactly once.
    verify(() => mockPlayerCubit.swapReconciledSong(-101, 501)).called(1);

    expect(states.any((s) => s.itemFor('testVid1').status == YtDownloadStatus.running),
        isTrue);
    await sub.cancel();
    await cubit.close();
  });

  test('download() does not re-submit while already queued or running',
      () async {
    final cubit = build();
    controller.add(DownloadsState(tasks: {
      'testVid1': taskWith(DownloadStatus.downloading),
    }));
    await Future.delayed(Duration.zero);

    await cubit.download(testSong);

    verifyNever(() => mockDownloads.queueDownload(any()));
    await cubit.close();
  });

  test('a failed task surfaces its error through the item', () async {
    final cubit = build();
    controller.add(DownloadsState(tasks: {
      'testVid1': taskWith(DownloadStatus.failed),
    }));
    await Future.delayed(Duration.zero);

    expect(cubit.state.itemFor('testVid1').status, YtDownloadStatus.failed);
    await cubit.close();
  });

  test('cancelDownload delegates to DownloadsCubit and marks the row canceled',
      () async {
    final cubit = build();
    cubit.cancelDownload('testVid1');
    expect(cubit.state.itemFor('testVid1').status, YtDownloadStatus.canceled);
    verify(() => mockDownloads.cancelDownload('testVid1')).called(1);
    await cubit.close();
  });

  test('downloadAll queues remote tracks and skips local ones', () async {
    final cubit = build();
    final localSong = const SongsTableData(
      id: 42,
      title: 'Local Song',
      artist: 'Local Artist',
      album: '',
      path: '/music/local.mp3',
      source: SongSource.local,
      remoteId: 'localVid1234',
      durationMs: 1000,
      isFavorite: false,
      playCount: 0,
      lastPositionMs: 0,
      isMissing: false,
      isDownloaded: true,
    );
    final count = cubit.downloadAll([testSong, localSong], maxBatch: 10);
    expect(count, 1);
    await Future.delayed(const Duration(milliseconds: 10));
    verify(() => mockDownloads.queueDownload(any())).called(1);
    await cubit.close();
  });
}
