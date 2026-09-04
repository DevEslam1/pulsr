import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/services/yt_download_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_download_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockYtDownloadService extends Mock implements YtDownloadService {}

class MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockYtDownloadService mockService;
  late MockPlayerCubit mockPlayerCubit;
  late SongsTableData testSong;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockService = MockYtDownloadService();
    mockPlayerCubit = MockPlayerCubit();
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

  group('YtmDownloadCubit State Transitions', () {
    test('initial state has empty download items', () {
      final cubit = YtmDownloadCubit(mockService, mockPlayerCubit);
      expect(cubit.state.items, isEmpty);
      expect(cubit.state.itemFor('nonexistent').status,
          equals(YtDownloadStatus.idle));
      cubit.close();
    });

    blocTest<YtmDownloadCubit, YtmDownloadState>(
      'transitions from idle -> queued -> running -> done on successful download',
      build: () {
        when(() => mockService.download(testSong,
                onProgress: any(named: 'onProgress')))
            .thenAnswer((invocation) async {
          final onProgress =
              invocation.namedArguments[const Symbol('onProgress')] as void
                  Function(YtDownloadProgress)?;
          onProgress?.call(const YtDownloadProgress(
              YtDownloadStage.downloading, 0.5, 512.0, 10));
          return const Right(501);
        });
        when(() => mockPlayerCubit.swapReconciledSong(any(), any()))
            .thenAnswer((_) async {});
        return YtmDownloadCubit(mockService, mockPlayerCubit);
      },
      act: (cubit) => cubit.download(testSong),
      expect: () => [
        isA<YtmDownloadState>().having(
          (s) => s.itemFor('testVid1').status,
          'status',
          YtDownloadStatus.queued,
        ),
        isA<YtmDownloadState>().having(
          (s) => s.itemFor('testVid1').status,
          'status',
          YtDownloadStatus.running,
        ),
        isA<YtmDownloadState>().having(
          (s) => s.itemFor('testVid1').status,
          'status',
          YtDownloadStatus.done,
        ),
      ],
    );

    blocTest<YtmDownloadCubit, YtmDownloadState>(
      'transitions from queued -> failed when service returns failure',
      build: () {
        when(() => mockService.download(testSong,
                onProgress: any(named: 'onProgress')))
            .thenAnswer((_) async =>
                const Left(DownloadFailure('Download network timeout')));
        return YtmDownloadCubit(mockService, mockPlayerCubit);
      },
      act: (cubit) => cubit.download(testSong),
      expect: () => [
        isA<YtmDownloadState>().having(
          (s) => s.itemFor('testVid1').status,
          'status',
          YtDownloadStatus.queued,
        ),
        isA<YtmDownloadState>()
            .having(
              (s) => s.itemFor('testVid1').status,
              'status',
              YtDownloadStatus.failed,
            )
            .having(
              (s) => s.itemFor('testVid1').error,
              'error',
              'Download network timeout',
            ),
      ],
    );

    blocTest<YtmDownloadCubit, YtmDownloadState>(
      'cancelDownload immediately transitions status to canceled and notifies service',
      build: () {
        when(() => mockService.cancel('testVid1')).thenReturn(null);
        return YtmDownloadCubit(mockService, mockPlayerCubit);
      },
      act: (cubit) => cubit.cancelDownload('testVid1'),
      expect: () => [
        isA<YtmDownloadState>().having(
          (s) => s.itemFor('testVid1').status,
          'status',
          YtDownloadStatus.canceled,
        ),
      ],
      verify: (_) {
        verify(() => mockService.cancel('testVid1')).called(1);
      },
    );
  });
}
