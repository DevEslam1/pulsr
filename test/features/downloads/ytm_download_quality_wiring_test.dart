// YtmDownloadButton wiring: the long-press quality picker's value must reach
// the download service's per-download override before the cubit queues the
// song. `routeDownloadQuality` is exercised directly so the check runs even
// when AppConfig.ytmEnabled compiles the button UI out.
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/yt_download_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/ytm_audio_quality.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_download_cubit.dart';
import 'package:pulsr/features/ytm_search/presentation/widgets/ytm_download_button.dart';

class MockYtmDownloadCubit extends Mock implements YtmDownloadCubit {}

class MockYtDownloadService extends Mock implements YtDownloadService {}

SongsTableData remoteSong(String videoId) => YtmTrack(
      videoId: videoId,
      title: 'Song',
      artist: 'Artist',
      duration: const Duration(minutes: 3),
    ).toSongData();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await getIt.reset();
  });

  test('the picker value reaches the service before the cubit queues',
      () async {
    final service = MockYtDownloadService();
    getIt.registerSingleton<YtDownloadService>(service);
    final cubit = MockYtmDownloadCubit();
    const videoId = 'vidWire00001';
    final song = remoteSong(videoId);
    when(() => cubit.download(song)).thenAnswer((_) async {});

    routeDownloadQuality(cubit, song, YtmAudioQuality.medium);

    verify(() =>
            service.setPendingDownloadQuality(videoId, YtmAudioQuality.medium))
        .called(1);
    verify(() => cubit.download(song)).called(1);
  });

  test('queues the download even when the service is not registered yet',
      () async {
    final cubit = MockYtmDownloadCubit();
    final song = remoteSong('vidWire00002');
    when(() => cubit.download(song)).thenAnswer((_) async {});

    routeDownloadQuality(cubit, song, YtmAudioQuality.high);

    verify(() => cubit.download(song)).called(1);
  });
}
