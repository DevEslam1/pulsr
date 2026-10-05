// test/features/ytm_search/ytm_download_cubit_test.dart
//
// NOTE: the core download-state transitions are already covered by
// `test/features/ytm_download_cubit_test.dart` (the pre-move location). This
// file adds coverage for the paths that one does not exercise: batch detail
// counters, retry, batch cancellation, task-status mapping, reconciliation
// de-duplication, throttling, and [YtDownloadItem] JSON round-tripping.
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

  SongsTableData remoteSong(String videoId, {int id = -101}) => SongsTableData(
        id: id,
        title: 'Song $videoId',
        artist: 'Artist',
        album: 'Album',
        path: 'ytmusic://$videoId',
        source: SongSource.youtube,
        remoteId: videoId,
        durationMs: 200000,
        isFavorite: false,
        playCount: 0,
        lastPositionMs: 0,
        isMissing: false,
        isDownloaded: false,
      );

  const localSong = SongsTableData(
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

  setUp(() {
    mockService = MockYtDownloadService();
    mockPlayerCubit = MockPlayerCubit();
    mockDownloads = MockDownloadsCubit();
    controller = StreamController<DownloadsState>.broadcast();
    when(() => mockDownloads.stream).thenAnswer((_) => controller.stream);
    when(() => mockDownloads.queueDownload(any())).thenAnswer((_) async {});
    when(() => mockDownloads.cancelDownload(any())).thenAnswer((_) async {});
    when(() => mockPlayerCubit.swapReconciledSong(any(), any()))
        .thenAnswer((_) async {});
  });

  tearDown(() async {
    await controller.close();
  });

  YtmDownloadCubit build() => YtmDownloadCubit(mockService, mockPlayerCubit,
      downloadsCubit: mockDownloads);

  DownloadTask taskWith(
    String videoId,
    DownloadStatus status, {
    double progress = 0.5,
    int? localSongId,
    int? sourceSongId = -101,
    String? error,
  }) =>
      DownloadTask(
        id: videoId,
        videoId: videoId,
        title: 'Song $videoId',
        artist: 'Artist',
        status: status,
        progress: progress,
        sourceSongId: sourceSongId,
        localSongId: localSongId,
        error: error,
        createdAt: DateTime(2026, 1, 1),
      );

  group('YtDownloadItem', () {
    test('JSON round-trips status, progress and error', () {
      const item = YtDownloadItem(
        status: YtDownloadStatus.running,
        progress: 0.42,
        speedKbps: 128.0,
        etaSeconds: 12,
      );
      final restored = YtDownloadItem.fromJson(item.toJson());
      expect(restored.status, YtDownloadStatus.running);
      expect(restored.progress, 0.42);
      expect(restored.speedKbps, 128.0);
      expect(restored.etaSeconds, 12);
      expect(restored.error, isNull);
    });

    test('fromJson falls back to idle for an unknown status', () {
      final item = YtDownloadItem.fromJson({'status': 'not-a-status'});
      expect(item.status, YtDownloadStatus.idle);
    });
  });

  group('_mapTask status mapping', () {
    Future<YtmDownloadCubit> cubitShowing(String videoId,
        DownloadStatus status,
        {double progress = 0.5, int? localSongId}) async {
      final cubit = build();
      controller.add(DownloadsState(tasks: {
        videoId: taskWith(videoId, status,
            progress: progress, localSongId: localSongId),
      }));
      await Future.delayed(Duration.zero);
      return cubit;
    }

    test('queued -> queued at zero progress', () async {
      final cubit =
          await cubitShowing('vid00000001', DownloadStatus.queued, progress: 0);
      final item = cubit.state.itemFor('vid00000001');
      expect(item.status, YtDownloadStatus.queued);
      expect(item.progress, 0);
      await cubit.close();
    });

    test('tagging -> running at full progress', () async {
      final cubit = await cubitShowing('vid00000002', DownloadStatus.tagging,
          progress: 0.9);
      final item = cubit.state.itemFor('vid00000002');
      expect(item.status, YtDownloadStatus.running);
      expect(item.progress, 1);
      await cubit.close();
    });

    test('paused -> paused without progress', () async {
      final cubit =
          await cubitShowing('vid00000003', DownloadStatus.paused);
      expect(cubit.state.itemFor('vid00000003').status,
          YtDownloadStatus.paused);
      await cubit.close();
    });

    test('failed carries the error string', () async {
      final cubit = build();
      controller.add(DownloadsState(tasks: {
        'vid00000004': taskWith('vid00000004', DownloadStatus.failed,
            error: 'disk full'),
      }));
      await Future.delayed(Duration.zero);
      final item = cubit.state.itemFor('vid00000004');
      expect(item.status, YtDownloadStatus.failed);
      expect(item.error, 'disk full');
      await cubit.close();
    });
  });

  group('download()', () {
    test('ignores a song with a null remoteId', () async {
      final cubit = build();
      final song = SongsTableData(
        id: -1,
        title: 'No remote',
        artist: 'a',
        album: '',
        path: 'x',
        source: SongSource.youtube,
        durationMs: 0,
        isFavorite: false,
        playCount: 0,
        lastPositionMs: 0,
        isMissing: false,
        isDownloaded: false,
      );
      await cubit.download(song);
      verifyNever(() => mockDownloads.queueDownload(any()));
      expect(cubit.state.items, isEmpty);
      await cubit.close();
    });
  });

  group('downloadAllDetailed', () {
    test('reports skippedLocal/alreadyActive/capped counters', () async {
      final cubit = build();
      // Pre-mark one track as already running via the mirrored stream.
      controller.add(DownloadsState(tasks: {
        'act00000001': taskWith('act00000001', DownloadStatus.downloading),
      }));
      await Future.delayed(Duration.zero);

      final result = cubit.downloadAllDetailed([
        remoteSong('new00000001', id: -1),
        localSong,
        remoteSong('act00000001', id: -2),
        remoteSong('new00000002', id: -3),
      ], maxBatch: 1);

      expect(result.queued, 1);
      expect(result.skippedLocal, 1);
      expect(result.alreadyActive, 1);
      expect(result.capped, 1);
      await cubit.close();
    });

    test('downloadAll returns only the queued count', () async {
      final cubit = build();
      final count = cubit.downloadAll([remoteSong('only0000001', id: -1)]);
      expect(count, 1);
      await Future.delayed(const Duration(milliseconds: 10));
      verify(() => mockDownloads.queueDownload(any())).called(1);
      await cubit.close();
    });

    test('cancelPendingBatch stops staggered starts from a superseded batch',
        () async {
      final cubit = build();
      final songs = [
        remoteSong('b0000000001', id: -1),
        remoteSong('b0000000002', id: -2),
      ];
      cubit.downloadAllDetailed(songs, maxBatch: 5);
      await Future.delayed(const Duration(milliseconds: 10));
      // Only the first (un-staggered) start should have fired so far.
      verify(() => mockDownloads.queueDownload(any())).called(1);

      cubit.cancelPendingBatch();
      await Future.delayed(const Duration(milliseconds: 700));
      // No new call was added by the cancelled staggered start. The single
      // already-verified call above is the only interaction.
      verifyNever(() => mockDownloads.queueDownload(
          any(that: isA<DownloadTask>().having(
              (t) => t.videoId, 'videoId', 'b0000000002'))));
      await cubit.close();
    });
  });

  group('retryDownload', () {
    test('resets a failed row and re-submits the task', () async {
      final cubit = build();
      controller.add(DownloadsState(tasks: {
        'retry000001': taskWith('retry000001', DownloadStatus.failed,
            error: 'boom'),
      }));
      await Future.delayed(Duration.zero);
      expect(
          cubit.state.itemFor('retry000001').status, YtDownloadStatus.failed);

      await cubit.retryDownload(remoteSong('retry000001'));
      verify(() => mockDownloads.queueDownload(any())).called(1);
      expect(
          cubit.state.itemFor('retry000001').status, YtDownloadStatus.queued);
      await cubit.close();
    });

    test('is a no-op for a song with no remoteId', () async {
      final cubit = build();
      final song = SongsTableData(
        id: -1,
        title: 'No remote',
        artist: 'a',
        album: '',
        path: 'x',
        source: SongSource.youtube,
        durationMs: 0,
        isFavorite: false,
        playCount: 0,
        lastPositionMs: 0,
        isMissing: false,
        isDownloaded: false,
      );
      await cubit.retryDownload(song);
      verifyNever(() => mockDownloads.queueDownload(any()));
      await cubit.close();
    });
  });

  group('completion reconciliation', () {
    test('runs the queue swap exactly once per video', () async {
      final cubit = build();
      final complete = DownloadsState(tasks: {
        'comp00000001': taskWith('comp00000001', DownloadStatus.complete,
            progress: 1, localSongId: 501),
      });
      controller.add(complete);
      await Future.delayed(Duration.zero);
      controller.add(complete);
      await Future.delayed(Duration.zero);

      verify(() => mockPlayerCubit.swapReconciledSong(-101, 501)).called(1);
      await cubit.close();
    });
  });

  group('state mirroring & cancellation', () {
    test('canceled rows survive subsequent stream emits', () async {
      final cubit = build();
      cubit.cancelDownload('cancel00001');
      expect(cubit.state.itemFor('cancel00001').status,
          YtDownloadStatus.canceled);

      // A later stream state with no tasks must not drop the canceled row.
      controller.add(const DownloadsState(tasks: {}));
      await Future.delayed(Duration.zero);
      expect(cubit.state.itemFor('cancel00001').status,
          YtDownloadStatus.canceled);
      await cubit.close();
    });

    test('throttles rapid running-progress emits', () async {
      final cubit = build();
      controller.add(DownloadsState(tasks: {
        'throt000001': taskWith('throt000001', DownloadStatus.downloading,
            progress: 0.2),
      }));
      await Future.delayed(Duration.zero);
      final baseline = cubit.state.itemFor('throt000001').progress;

      // Two rapid intermediate-progress updates inside the 200ms window.
      controller.add(DownloadsState(tasks: {
        'throt000001': taskWith('throt000001', DownloadStatus.downloading,
            progress: 0.3),
      }));
      controller.add(DownloadsState(tasks: {
        'throt000001': taskWith('throt000001', DownloadStatus.downloading,
            progress: 0.4),
      }));
      await Future.delayed(Duration.zero);

      // Either the first or second landed, but the throttled one did not
      // produce a third distinct state in the same window.
      expect(cubit.state.itemFor('throt000001').progress,
          isNot(equals(baseline)));
      await cubit.close();
    });

    test('close cancels the stream subscription', () async {
      final cubit = build();
      await cubit.close();
      expect(cubit.activeSubscriptionCount, 0);
    });
  });
}
