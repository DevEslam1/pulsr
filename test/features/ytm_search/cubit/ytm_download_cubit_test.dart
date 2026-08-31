import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/data/downloads/yt_download_service.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_download_cubit.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/repositories/download_repository_interface.dart';
import 'package:pulsr/domain/usecases/queue_download.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockYtDownloadService extends Mock implements YtDownloadService {}

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockSongsTableData extends Mock implements SongsTableData {}

class MockDownloadRepo extends Mock implements IDownloadRepository {}


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late YtmDownloadCubit cubit;
  late MockYtDownloadService mockService;
  late MockPlayerCubit mockPlayerCubit;

  setUpAll(() {
    registerFallbackValue(MockSongsTableData());
    registerFallbackValue(DownloadTask(
      id: 'fallback',
      videoId: 'fallback',
      title: 'Fallback',
      artist: 'Fallback',
      createdAt: DateTime.now(),
    ));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockService = MockYtDownloadService();
    mockPlayerCubit = MockPlayerCubit();
    cubit = YtmDownloadCubit(mockService, mockPlayerCubit);
  });

  tearDown(() => cubit.close());

  group('YtmDownloadCubit', () {
    final mockSong = MockSongsTableData();

    setUp(() {
      when(() => mockSong.remoteId).thenReturn('test_video_id');
      when(() => mockSong.id).thenReturn(123);
    });

    test('initial state is correct', () {
      expect(cubit.state, const YtmDownloadState());
    });

    blocTest<YtmDownloadCubit, YtmDownloadState>(
      'emits [queued, running, done] on successful download',
      build: () {
        when(() => mockService.download(any(),
                onProgress: any(named: 'onProgress')))
            .thenAnswer((invocation) async {
          final onProgress = invocation.namedArguments[#onProgress] as void
              Function(YtDownloadProgress)?;
          onProgress?.call(
              const YtDownloadProgress(YtDownloadStage.downloading, 0.5));
          return const Right(123);
        });
        when(() => mockPlayerCubit.swapReconciledSong(any(), any()))
            .thenAnswer((_) async {});
        return cubit;
      },
      act: (cubit) => cubit.download(mockSong),
      expect: () => [
        isA<YtmDownloadState>().having((s) => s.itemFor('test_video_id').status,
            'status', YtDownloadStatus.queued),
        isA<YtmDownloadState>().having((s) => s.itemFor('test_video_id').status,
            'status', YtDownloadStatus.running),
        isA<YtmDownloadState>().having((s) => s.itemFor('test_video_id').status,
            'status', YtDownloadStatus.done),
      ],
      verify: (_) {
        verify(() => mockPlayerCubit.swapReconciledSong(123, 123)).called(1);
      },
    );

    blocTest<YtmDownloadCubit, YtmDownloadState>(
      'emits [queued, failed] on download failure',
      build: () {
        when(() => mockService.download(any(),
                onProgress: any(named: 'onProgress')))
            .thenAnswer(
                (_) async => const Left(DownloadFailure('Network Error')));
        return cubit;
      },
      act: (cubit) => cubit.download(mockSong),
      expect: () => [
        isA<YtmDownloadState>().having((s) => s.itemFor('test_video_id').status,
            'status', YtDownloadStatus.queued),
        isA<YtmDownloadState>()
            .having((s) => s.itemFor('test_video_id').status, 'status',
                YtDownloadStatus.failed)
            .having((s) => s.itemFor('test_video_id').error, 'error',
                'Network Error'),
      ],
    );

    blocTest<YtmDownloadCubit, YtmDownloadState>(
      'cancels download and emits canceled state',
      build: () {
        when(() => mockService.cancel(any())).thenReturn(null);
        return cubit;
      },
      act: (cubit) => cubit.cancelDownload('test_video_id'),
      expect: () => [
        isA<YtmDownloadState>().having((s) => s.itemFor('test_video_id').status,
            'status', YtDownloadStatus.canceled),
      ],
      verify: (_) {
        verify(() => mockService.cancel('test_video_id')).called(1);
      },
    );

    blocTest<YtmDownloadCubit, YtmDownloadState>(
      'ignores download request if already running or done',
      build: () {
        when(() => mockService.download(any(),
                onProgress: any(named: 'onProgress')))
            .thenAnswer((_) async => const Right(123));
        when(() => mockPlayerCubit.swapReconciledSong(any(), any()))
            .thenAnswer((_) async {});
        return cubit;
      },
      act: (cubit) async {
        await cubit.download(mockSong);
        await cubit.download(mockSong); // Should be ignored
      },
      expect: () => [
        isA<YtmDownloadState>().having((s) => s.itemFor('test_video_id').status,
            'status', YtDownloadStatus.queued),
        isA<YtmDownloadState>().having((s) => s.itemFor('test_video_id').status,
            'status', YtDownloadStatus.done),
      ],
    );

    test(
        'downloadAll queues eligible online songs and skips local/duplicate tracks',
        () async {
      final song1 = MockSongsTableData();
      final song2 = MockSongsTableData();
      final localSong = MockSongsTableData();

      when(() => song1.remoteId).thenReturn('video_1');
      when(() => song1.id).thenReturn(1);
      when(() => song1.source).thenReturn(SongSource.youtube);

      when(() => song2.remoteId).thenReturn('video_2');
      when(() => song2.id).thenReturn(2);
      when(() => song2.source).thenReturn(SongSource.youtube);

      when(() => localSong.remoteId).thenReturn('video_local');
      when(() => localSong.id).thenReturn(3);
      when(() => localSong.source).thenReturn(SongSource.local);

      when(() =>
              mockService.download(any(), onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => const Right(1));
      when(() => mockPlayerCubit.swapReconciledSong(any(), any()))
          .thenAnswer((_) async {});

      final count = cubit.downloadAll([song1, song2, localSong]);
      expect(count, 2);

      // Subsequent call should skip already queued items
      final countAgain = cubit.downloadAll([song1, song2]);
      expect(countAgain, 0);
    });

    test('initializes download states from IDownloadRepository stream and query (DL-17)',
        () async {
      final mockRepo = MockDownloadRepo();
      when(() => mockRepo.getAllDownloads()).thenAnswer((_) async => [
            DownloadTask(
              id: 't1',
              videoId: 'v1',
              title: 'Song 1',
              artist: 'Artist 1',
              createdAt: DateTime.now(),
              status: DownloadStatus.downloading,
            ),
            DownloadTask(
              id: 't2',
              videoId: 'v2',
              title: 'Song 2',
              artist: 'Artist 2',
              createdAt: DateTime.now(),
              status: DownloadStatus.complete,
            ),
          ]);
      when(() => mockRepo.observeDownloads()).thenAnswer((_) => const Stream.empty());

      final newCubit = YtmDownloadCubit(mockService, mockPlayerCubit, mockRepo);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(newCubit.state.itemFor('v1').status, YtDownloadStatus.running);
      expect(newCubit.state.itemFor('v2').status, YtDownloadStatus.done);
      await newCubit.close();
    });
  });

  group('YtmDownloadCubit use-case path: player swap on completion', () {
    // Real QueueDownloadUseCase wrapping the mock repository keeps the
    // production wiring (cubit → use case → repository) under test.
    test('search-initiated download swaps the player row to the reconciled '
        'library song on completion', () async {
      final mockRepo = MockDownloadRepo();
      getIt.registerSingleton<QueueDownloadUseCase>(
        QueueDownloadUseCase(mockRepo),
      );
      addTearDown(getIt.reset);

      final repoEvents = StreamController<DownloadTask>.broadcast();
      when(() => mockRepo.getAllDownloads()).thenAnswer((_) async => []);
      when(() => mockRepo.observeDownloads())
          .thenAnswer((_) => repoEvents.stream);
      when(() => mockRepo.queueDownload(any()))
          .thenAnswer((_) async => const Right('yt_test_video_id'));
      when(() => mockPlayerCubit.swapReconciledSong(any(), any()))
          .thenAnswer((_) async {});

      final cubit = YtmDownloadCubit(mockService, mockPlayerCubit, mockRepo);
      addTearDown(cubit.close);
      addTearDown(repoEvents.close);

      final song = SongsTableData(
        id: 123,
        title: 'Search Row',
        artist: 'Artist',
        album: 'Album',
        durationMs: 1000,
        path: 'ytmusic://test_video_id',
        source: SongSource.youtube,
        remoteId: 'test_video_id',
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
      );

      await cubit.download(song);
      expect(cubit.state.itemFor('test_video_id').status,
          YtDownloadStatus.queued,
          reason: 'use-case path must queue through the shared repository');
      verifyNever(() => mockService.download(any(),
          onProgress: any(named: 'onProgress')));

      // Repository reports the completed download with the reconciled
      // positive-id library row.
      repoEvents.add(DownloadTask(
        id: 'yt_test_video_id',
        videoId: 'test_video_id',
        title: 'Search Row',
        artist: 'Artist',
        createdAt: DateTime.now(),
        status: DownloadStatus.complete,
        progress: 1.0,
        librarySongId: 456,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 400));

      verify(() => mockPlayerCubit.swapReconciledSong(123, 456)).called(1);
      expect(cubit.state.itemFor('test_video_id').status,
          YtDownloadStatus.done);
    });

    test('failed download does not trigger the player swap', () async {
      final mockRepo = MockDownloadRepo();
      getIt.registerSingleton<QueueDownloadUseCase>(
        QueueDownloadUseCase(mockRepo),
      );
      addTearDown(getIt.reset);

      final repoEvents = StreamController<DownloadTask>.broadcast();
      when(() => mockRepo.getAllDownloads()).thenAnswer((_) async => []);
      when(() => mockRepo.observeDownloads())
          .thenAnswer((_) => repoEvents.stream);
      when(() => mockRepo.queueDownload(any())).thenAnswer(
          (_) async => const Left(DownloadFailure('Network down')));
      when(() => mockPlayerCubit.swapReconciledSong(any(), any()))
          .thenAnswer((_) async {});

      final cubit = YtmDownloadCubit(mockService, mockPlayerCubit, mockRepo);
      addTearDown(cubit.close);
      addTearDown(repoEvents.close);

      final song = SongsTableData(
        id: 123,
        title: 'Search Row',
        artist: 'Artist',
        album: 'Album',
        durationMs: 1000,
        path: 'ytmusic://test_video_id',
        source: SongSource.youtube,
        remoteId: 'test_video_id',
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
      );

      await cubit.download(song);
      expect(cubit.state.itemFor('test_video_id').status,
          YtDownloadStatus.failed);

      repoEvents.add(DownloadTask(
        id: 'yt_test_video_id',
        videoId: 'test_video_id',
        title: 'Search Row',
        artist: 'Artist',
        createdAt: DateTime.now(),
        status: DownloadStatus.failed,
        error: 'Network down',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 400));

      verifyNever(() => mockPlayerCubit.swapReconciledSong(any(), any()));
    });
  });
}

