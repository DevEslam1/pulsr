// Coverage for the uncovered branches of player_cubit.dart.
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/hires_audio_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player_test_support.dart';

class MockHiResAudioService extends Mock implements HiResAudioService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordingAudioHandler handler;
  late MockMusicRepository repo;
  late MockToggleFavoriteUseCase toggleFavorite;

  setUpAll(() {
    registerFallbackValue(buildSong(0));
    registerFallbackValue(Duration.zero);
    registerFallbackValue(const SettingsState());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    handler = RecordingAudioHandler()
      ..realLoadQueue = true
      ..realSeek = true;
    repo = MockMusicRepository();
    toggleFavorite = MockToggleFavoriteUseCase();
    when(() => repo.getSongById(any()))
        .thenAnswer((_) async => right(null));
    when(() => repo.getSongsByIds(any()))
        .thenAnswer((_) async => right(<SongsTableData>[]));
    when(() => repo.findMatchingLocalSong(
          remoteId: any(named: 'remoteId'),
          title: any(named: 'title'),
          artist: any(named: 'artist'),
        )).thenAnswer((_) async => right(null));
  });

  PlayerCubit buildCubit({
    MockSettingsCubit? settingsCubit,
    MockHiResAudioService? hiRes,
  }) =>
      PlayerCubit(
        audioHandler: handler,
        repository: repo,
        toggleFavoriteUseCase: toggleFavorite,
        settingsCubit: settingsCubit,
        hiResAudioService: hiRes,
      );

  group('mediaItem resolution', () {
    test('non-numeric id resolves to a synthetic song with extras',
        () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      handler.emitMediaItem(MediaItem(
        id: 'yt_abc',
        title: 'Streamed',
        artist: 'Artist',
        album: 'Album',
        duration: const Duration(seconds: 100),
        artUri: Uri.parse('http://art/x.jpg'),
        extras: const {
          'path': 'ytmusic://abc',
          'source': 'youtube',
          'remoteId': 'abc',
          'isFavorite': true,
          'isDownloaded': true,
          'playCount': 4,
        },
      ));
      await pumpEventQueue();

      final song = cubit.state.currentSong;
      expect(song, isNotNull);
      expect(song!.id, lessThan(0));
      expect(song.title, 'Streamed');
      expect(song.source, SongSource.youtube);
      expect(song.remoteId, 'abc');
      expect(song.isFavorite, isTrue);
      expect(song.playCount, 4);
      expect(cubit.state.duration, const Duration(seconds: 100));
    });

    test('a null media item while idle clears the current song', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      handler.emitTrackChanged(buildSong(1));
      await pumpEventQueue();
      expect(cubit.state.currentSong, isNotNull);

      handler.emitMediaItem(null);
      await pumpEventQueue();

      expect(cubit.state.currentSong, isNull);
      expect(cubit.state.isPlaying, isFalse);
    });

    test('a media item with an empty id is treated as null', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      handler.emitTrackChanged(buildSong(1));
      await pumpEventQueue();

      handler.emitMediaItem(const MediaItem(id: '', title: 'Ignored'));
      await pumpEventQueue();

      expect(cubit.state.currentSong, isNull);
    });

    test('resolves a numeric id through the repository', () async {
      final song = buildSong(7);
      when(() => repo.getSongById(7))
          .thenAnswer((_) async => right(song));
      final cubit = buildCubit();
      addTearDown(cubit.close);

      handler.emitMediaItem(const MediaItem(
        id: '7',
        title: 'Seven',
        artist: 'Artist',
        duration: Duration(seconds: 30),
      ));
      await pumpEventQueue();

      expect(cubit.state.currentSong?.id, 7);
      expect(cubit.state.currentSong?.title, 'Song 7');
    });
  });

  group('track change resolution', () {
    test('preserves duration when the same song restarts with zero duration',
        () async {
      final song = buildSong(5, durationMs: 0);
      final cubit = buildCubit();
      addTearDown(cubit.close);

      handler.emitTrackChanged(song);
      await pumpEventQueue();
      handler.emitTrackChanged(song);
      await pumpEventQueue();

      expect(cubit.state.duration, Duration.zero);
      expect(cubit.state.currentSong?.id, 5);
    });

    test('treats a matching remoteId as the same track', () async {
      final a = buildSong(1, remoteId: 'shared');
      final b = buildSong(99, remoteId: 'shared');
      final cubit = buildCubit();
      addTearDown(cubit.close);

      handler.emitTrackChanged(a);
      await pumpEventQueue();
      cubit.setStateForTesting(cubit.state.copyWith(
        lyricsSlice: cubit.state.lyricsSlice.copyWith(
          lyrics: const [
            LyricsLine(timestamp: Duration.zero, text: 'kept'),
          ],
        ),
      ));

      handler.emitTrackChanged(b);
      await pumpEventQueue();

      expect(cubit.state.currentSong?.id, 99);
      // Same-track: lyrics are preserved.
      expect(cubit.state.lyrics.length, 1);
    });
  });

  group('queue restoration', () {
    test('non-numeric queue ids become synthetic songs', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      handler.emitQueue([
        const MediaItem(
          id: 'yt_q1',
          title: 'Queue Stream',
          artist: 'Q Artist',
          extras: {'remoteId': 'q1', 'source': 'youtube'},
        ),
      ]);
      await pumpEventQueue();

      expect(cubit.state.queue.length, 1);
      expect(cubit.state.queue.first.id, lessThan(0));
      expect(cubit.state.queue.first.remoteId, 'q1');
    });

    test('an empty queue event clears the live queue', () async {
      final song = buildSong(1);
      when(() => repo.getSongsByIds([1]))
          .thenAnswer((_) async => right([song]));
      final cubit = buildCubit();
      addTearDown(cubit.close);

      handler.emitQueue([const MediaItem(id: '1', title: 'Song 1')]);
      await pumpEventQueue();
      expect(cubit.state.queue, isNotEmpty);

      handler.emitQueue([]);
      await pumpEventQueue();
      expect(cubit.state.queue, isEmpty);
      expect(cubit.state.currentSong, isNull);
    });
  });

  group('playbackState branches', () {
    test('completed playback resets the position and stops', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      handler.emitPlaybackState(PlaybackState(
        processingState: AudioProcessingState.ready,
        playing: true,
        updatePosition: const Duration(seconds: 30),
      ));
      await pumpEventQueue();
      expect(cubit.state.isPlaying, isTrue);

      handler.emitPlaybackState(PlaybackState(
        processingState: AudioProcessingState.completed,
        playing: false,
        updatePosition: const Duration(seconds: 30),
      ));
      await pumpEventQueue();

      expect(cubit.state.isPlaying, isFalse);
      expect(cubit.state.position, Duration.zero);
    });

    test('keeps optimistic playing through a transient loading state',
        () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      handler.emitPlaybackState(PlaybackState(
        processingState: AudioProcessingState.ready,
        playing: true,
      ));
      await pumpEventQueue();
      expect(cubit.state.isPlaying, isTrue);

      handler.emitPlaybackState(PlaybackState(
        processingState: AudioProcessingState.buffering,
        playing: false,
      ));
      await pumpEventQueue();

      expect(cubit.state.isPlaying, isTrue);
    });

    test('maps every repeat mode', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      handler.emitPlaybackState(PlaybackState(
        processingState: AudioProcessingState.ready,
        repeatMode: AudioServiceRepeatMode.one,
      ));
      await pumpEventQueue();
      expect(cubit.state.repeatMode, PlayerRepeatMode.one);

      handler.emitPlaybackState(PlaybackState(
        processingState: AudioProcessingState.ready,
        repeatMode: AudioServiceRepeatMode.group,
      ));
      await pumpEventQueue();
      expect(cubit.state.repeatMode, PlayerRepeatMode.all);
    });
  });

  group('settings reaction', () {
    test('re-applies volume, crossfade and gapless on settings changes',
        () async {
      final settings = MockSettingsCubit();
      final controller = StreamController<SettingsState>.broadcast();
      var current = const SettingsState();
      when(() => settings.state).thenAnswer((_) => current);
      when(() => settings.stream).thenAnswer((_) => controller.stream);

      final cubit = buildCubit(settingsCubit: settings);
      addTearDown(cubit.close);
      addTearDown(controller.close);
      final before = handler.setVolumeCallCount;

      current = current.copyWith(crossfadeSeconds: 5.0);
      controller.add(current);
      await pumpEventQueue();
      expect(handler.currentCrossfadeDuration, const Duration(seconds: 5));

      current = current.copyWith(gaplessPlayback: false);
      controller.add(current);
      await pumpEventQueue();
      expect(handler.gaplessEnabled, isFalse);

      current = current.copyWith(replayGainPreampWithRg: 2.0);
      controller.add(current);
      await pumpEventQueue();
      expect(handler.setVolumeCallCount, greaterThan(before));
    });

    test('follows the track sample rate when both flags turn on', () async {
      final settings = MockSettingsCubit();
      final controller = StreamController<SettingsState>.broadcast();
      var current = const SettingsState();
      when(() => settings.state).thenAnswer((_) => current);
      when(() => settings.stream).thenAnswer((_) => controller.stream);

      final hiRes = MockHiResAudioService();
      when(() => hiRes.setTargetOutputFormat(
            sampleRate: any(named: 'sampleRate'),
            bitDepth: any(named: 'bitDepth'),
          )).thenAnswer((_) async => true);
      when(() => settings.refreshOutputDevice()).thenAnswer((_) async {});

      final cubit = buildCubit(settingsCubit: settings, hiRes: hiRes);
      addTearDown(cubit.close);
      addTearDown(controller.close);

      handler.emitTrackChanged(
          buildSong(1, durationMs: 100000, sampleRate: 44100, bitDepth: 16));
      await pumpEventQueue();

      current = current.copyWith(
        followTrackSampleRate: true,
        bitPerfectOutput: true,
      );
      controller.add(current);
      await pumpEventQueue();

      verify(() => hiRes.setTargetOutputFormat(
            sampleRate: any(named: 'sampleRate'),
            bitDepth: any(named: 'bitDepth'),
          )).called(greaterThanOrEqualTo(1));
    });
  });

  group('misc branches', () {
    test('clearError clears a queue-overflow error', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      final full = List.generate(500, (i) => buildSong(i + 1));
      await cubit.playSong(full.first, queue: full);
      await cubit.playNext(buildSong(9999));
      expect(cubit.state.errorMessage, contains('Queue full'));

      cubit.clearError();
      expect(cubit.state.errorMessage, isNull);
    });

    test('invalidation and snapshot helpers are callable', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);
      expect(cubit.rawPositionStream, isNotNull);
      cubit.invalidateMediaItemResolution();
      cubit.invalidateQueueSyncResolution();
      await cubit.persistQueueSlotsNow();
    });

    test('setStateForTesting installs a pre-baked state', () {
      final cubit = buildCubit();
      addTearDown(cubit.close);
      final baked = PlayerState(
        queueSlice: const QueueSlice().copyWith(
          queue: [buildSong(1)],
          currentIndex: 0,
        ),
      );
      cubit.setStateForTesting(baked);
      expect(cubit.state.queue.length, 1);
    });
  });
}
