// Live-radio transport semantics: Pause acts as stop and Play re-seeks to the
// live edge instead of resuming a stale buffer.
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/radio_station.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player/player_test_support.dart';

class _RadioHandler extends RecordingAudioHandler {
  final List<Duration> seeks = <Duration>[];

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek');
    seeks.add(position);
  }

  @override
  Future<void> seekDirect(Duration position) async {
    calls.add('seekDirect');
    seeks.add(position);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RadioHandler handler;
  late MockMusicRepository repo;
  late MockToggleFavoriteUseCase toggleFavorite;
  late RadioStation station;

  setUpAll(() {
    registerFallbackValue(buildSong(0));
    registerFallbackValue(Duration.zero);
    registerFallbackValue(const SettingsState());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    handler = _RadioHandler();
    repo = MockMusicRepository();
    toggleFavorite = MockToggleFavoriteUseCase();
    station = RadioStation.create(
      name: 'Live FM',
      url: 'https://stream.example.com/live.mp3',
      genre: 'Jazz',
    );
    when(() => repo.getSongById(any())).thenAnswer((_) async => right(null));
    when(() => repo.getSongsByIds(any()))
        .thenAnswer((_) async => right(<SongsTableData>[]));
    when(() => repo.findMatchingLocalSong(
          remoteId: any(named: 'remoteId'),
          title: any(named: 'title'),
          artist: any(named: 'artist'),
        )).thenAnswer((_) async => right(null));
  });

  PlayerCubit buildCubit() => PlayerCubit(
        audioHandler: handler,
        repository: repo,
        toggleFavoriteUseCase: toggleFavorite,
      );

  test('playRadioStation marks the current song as a live radio stream',
      () async {
    final cubit = buildCubit();
    addTearDown(cubit.close);

    await cubit.playRadioStation(station);

    expect(cubit.state.currentSong?.source, SongSource.radio);
    expect(cubit.state.currentSong?.path, station.url);
  });

  test('pause on a live stream stops playback and drops the stale position',
      () async {
    final cubit = buildCubit();
    addTearDown(cubit.close);

    await cubit.playRadioStation(station);
    handler.emitPlaybackState(PlaybackState(
      processingState: AudioProcessingState.ready,
      playing: true,
    ));
    await pumpEventQueue();
    expect(cubit.state.isPlaying, isTrue);

    await cubit.togglePlayPause();

    expect(handler.pauseCalls, 1);
    expect(handler.playCalls, 0);
    expect(cubit.state.isPlaying, isFalse);
    expect(cubit.state.position, Duration.zero);
  });

  test('play on a paused live stream re-seeks to live before playing',
      () async {
    final cubit = buildCubit();
    addTearDown(cubit.close);

    await cubit.playRadioStation(station);
    await cubit.pause();
    await pumpEventQueue();
    final seeksBefore = handler.seeks.length;

    await cubit.togglePlayPause();
    await pumpEventQueue();

    expect(handler.seeks.length, seeksBefore + 1);
    expect(handler.seeks.last, Duration.zero);
    expect(handler.playCalls, 1);
    expect(cubit.state.isPlaying, isTrue);
  });

  test('regular tracks keep the plain pause path without a live re-seek',
      () async {
    final cubit = buildCubit();
    addTearDown(cubit.close);

    final song = buildSong(7);
    await cubit.playSong(song);
    await cubit.pause();

    expect(handler.pauseCalls, 1);
    expect(handler.seeks, isEmpty);
  });
}
