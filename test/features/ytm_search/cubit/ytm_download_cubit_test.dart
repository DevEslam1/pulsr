import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pulsr/core/services/yt_download_service.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_download_cubit.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockYtDownloadService extends Mock implements YtDownloadService {}
class MockPlayerCubit extends Mock implements PlayerCubit {}
class MockSongsTableData extends Mock implements SongsTableData {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late YtmDownloadCubit cubit;
  late MockYtDownloadService mockService;
  late MockPlayerCubit mockPlayerCubit;

  setUpAll(() {
    registerFallbackValue(MockSongsTableData());
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
        when(() => mockService.download(any(), onProgress: any(named: 'onProgress')))
            .thenAnswer((invocation) async {
          final onProgress = invocation.namedArguments[#onProgress] as void Function(YtDownloadProgress)?;
          onProgress?.call(const YtDownloadProgress(YtDownloadStage.downloading, 0.5));
          return const Right(123);
        });
        when(() => mockPlayerCubit.swapReconciledSong(any(), any()))
            .thenAnswer((_) async {});
        return cubit;
      },
      act: (cubit) => cubit.download(mockSong),
      expect: () => [
        isA<YtmDownloadState>().having((s) => s.itemFor('test_video_id').status, 'status', YtDownloadStatus.queued),
        isA<YtmDownloadState>().having((s) => s.itemFor('test_video_id').status, 'status', YtDownloadStatus.running),
        isA<YtmDownloadState>().having((s) => s.itemFor('test_video_id').status, 'status', YtDownloadStatus.done),
      ],
      verify: (_) {
        verify(() => mockPlayerCubit.swapReconciledSong(123, 123)).called(1);
      },
    );

    blocTest<YtmDownloadCubit, YtmDownloadState>(
      'emits [queued, failed] on download failure',
      build: () {
        when(() => mockService.download(any(), onProgress: any(named: 'onProgress')))
            .thenAnswer((_) async => const Left(DownloadFailure('Network Error')));
        return cubit;
      },
      act: (cubit) => cubit.download(mockSong),
      expect: () => [
        isA<YtmDownloadState>().having((s) => s.itemFor('test_video_id').status, 'status', YtDownloadStatus.queued),
        isA<YtmDownloadState>()
            .having((s) => s.itemFor('test_video_id').status, 'status', YtDownloadStatus.failed)
            .having((s) => s.itemFor('test_video_id').error, 'error', 'Network Error'),
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
        isA<YtmDownloadState>().having((s) => s.itemFor('test_video_id').status, 'status', YtDownloadStatus.canceled),
      ],
      verify: (_) {
        verify(() => mockService.cancel('test_video_id')).called(1);
      },
    );

    blocTest<YtmDownloadCubit, YtmDownloadState>(
      'ignores download request if already running or done',
      build: () {
        when(() => mockService.download(any(), onProgress: any(named: 'onProgress')))
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
        isA<YtmDownloadState>().having((s) => s.itemFor('test_video_id').status, 'status', YtDownloadStatus.queued),
        isA<YtmDownloadState>().having((s) => s.itemFor('test_video_id').status, 'status', YtDownloadStatus.done),
      ],
    );

    test('downloadAll queues eligible online songs and skips local/duplicate tracks', () async {
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

      when(() => mockService.download(any(), onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => const Right(1));
      when(() => mockPlayerCubit.swapReconciledSong(any(), any()))
          .thenAnswer((_) async {});

      final count = cubit.downloadAll([song1, song2, localSong]);
      expect(count, 2);

      // Subsequent call should skip already queued items
      final countAgain = cubit.downloadAll([song1, song2]);
      expect(countAgain, 0);
    });
  });
}
