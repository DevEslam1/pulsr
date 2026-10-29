// YtmDownloadButton wiring: the long-press quality picker's value must reach
// the queued task (which persists it) before the repository admits it, and the
// picker must open on the user's persisted default. `routeDownloadQuality` is
// exercised directly so the check runs even when AppConfig.ytmEnabled compiles
// the button UI out.
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/ytm_audio_quality.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_download_cubit.dart';
import 'package:pulsr/features/ytm_search/presentation/widgets/ytm_download_button.dart';

class MockYtmDownloadCubit extends Mock implements YtmDownloadCubit {}

SongsTableData remoteSong(String videoId) => YtmTrack(
      videoId: videoId,
      title: 'Song',
      artist: 'Artist',
      duration: const Duration(minutes: 3),
    ).toSongData();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(YtmAudioQuality.high);
  });

  test('the picker value is carried on the queued task', () async {
    final cubit = MockYtmDownloadCubit();
    final song = remoteSong('vidWire00001');
    when(() => cubit.download(song, quality: any(named: 'quality')))
        .thenAnswer((_) async {});

    routeDownloadQuality(cubit, song, YtmAudioQuality.medium);

    verify(() => cubit.download(song, quality: YtmAudioQuality.medium))
        .called(1);
  });

  test('the picker opens on the persisted default quality', () {
    expect(downloadQualityFromSetting('low'), YtmAudioQuality.low);
    expect(downloadQualityFromSetting(' MEDIUM '), YtmAudioQuality.medium);
    expect(downloadQualityFromSetting('high'), YtmAudioQuality.high);
    expect(downloadQualityFromSetting(null), YtmAudioQuality.high);
    expect(downloadQualityFromSetting('legacy'), YtmAudioQuality.high);
  });
}
