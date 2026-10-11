// Coverage for the additive PlaybackSlice.isBuffering field and the
// skip-on-consecutive-error recovery in PlayerCubit.
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player_test_support.dart';

class _ErrorEmittingHandler extends RecordingAudioHandler {
  final StreamController<String> _errors = StreamController<String>.broadcast();

  int skipToNextCalls = 0;
  int skipToPreviousCalls = 0;

  @override
  Stream<String> get errorStream => _errors.stream;

  void emitError(String error) => _errors.add(error);

  @override
  Future<void> skipToNext() async {
    skipToNextCalls++;
  }

  @override
  Future<void> skipToPrevious() async {
    skipToPreviousCalls++;
  }

  @override
  Future<void> dispose() async {
    await _errors.close();
    await super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ErrorEmittingHandler handler;
  late MockMusicRepository repo;
  late MockToggleFavoriteUseCase toggleFavorite;

  setUpAll(() {
    registerFallbackValue(buildSong(0));
    registerFallbackValue(Duration.zero);
    registerFallbackValue(const SettingsState());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    handler = _ErrorEmittingHandler();
    repo = MockMusicRepository();
    toggleFavorite = MockToggleFavoriteUseCase();
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

  group('isBuffering', () {
    test('loading and buffering processing states set the flag', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      handler.emitPlaybackState(PlaybackState(
        processingState: AudioProcessingState.loading,
        playing: true,
      ));
      await pumpEventQueue();
      expect(cubit.state.isBuffering, isTrue);
      expect(cubit.state.isPlaying, isTrue);

      handler.emitPlaybackState(PlaybackState(
        processingState: AudioProcessingState.buffering,
        playing: true,
      ));
      await pumpEventQueue();
      expect(cubit.state.isBuffering, isTrue);

      handler.emitPlaybackState(PlaybackState(
        processingState: AudioProcessingState.ready,
        playing: true,
      ));
      await pumpEventQueue();
      expect(cubit.state.isBuffering, isFalse);
      expect(cubit.state.isPlaying, isTrue);
    });

    test(
        'a mid-playback stall clears the flag once ready without losing '
        'the paused intent', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      handler.emitPlaybackState(PlaybackState(
        processingState: AudioProcessingState.ready,
        playing: true,
      ));
      await pumpEventQueue();

      handler.emitPlaybackState(PlaybackState(
        processingState: AudioProcessingState.buffering,
        playing: false,
      ));
      await pumpEventQueue();
      // Optimistic play is retained through the transient stall.
      expect(cubit.state.isPlaying, isTrue);
      expect(cubit.state.isBuffering, isTrue);

      handler.emitPlaybackState(PlaybackState(
        processingState: AudioProcessingState.ready,
        playing: false,
      ));
      await pumpEventQueue();
      expect(cubit.state.isBuffering, isFalse);
      expect(cubit.state.isPlaying, isFalse);
    });

    test('an engine error clears the buffering flag', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      handler.emitPlaybackState(PlaybackState(
        processingState: AudioProcessingState.buffering,
        playing: true,
      ));
      await pumpEventQueue();
      expect(cubit.state.isBuffering, isTrue);

      handler.emitError('decoder exploded');
      await pumpEventQueue();
      expect(cubit.state.isBuffering, isFalse);
      expect(cubit.state.errorMessage, 'decoder exploded');
    });

    test('differsFromBeyondPosition reacts to buffering changes', () {
      const base = PlayerState();
      final buffering = base.copyWith(
        playback: base.playback.copyWith(isBuffering: true),
      );
      expect(base.differsFromBeyondPosition(buffering), isTrue);
      expect(buffering.differsFromBeyondPosition(base), isTrue);
    });
  });

  group('skip-on-error recovery', () {
    test('the first failure surfaces the error without skipping', () async {
      final song1 = buildSong(1);
      final song2 = buildSong(2);
      final cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.playSong(song1, queue: [song1, song2]);

      handler.emitError('decode failed');
      await pumpEventQueue();

      expect(cubit.state.errorMessage, 'decode failed');
      expect(handler.skipToNextCalls, 0);
    });

    test('the second consecutive failure of the same item auto-advances',
        () async {
      final song1 = buildSong(1);
      final song2 = buildSong(2);
      final cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.playSong(song1, queue: [song1, song2]);

      handler.emitError('decode failed');
      await pumpEventQueue();
      expect(handler.skipToNextCalls, 0);

      handler.emitError('decode failed again');
      await pumpEventQueue();

      expect(cubit.state.errorMessage, 'Skipped Song 1 (unplayable)');
      expect(handler.skipToNextCalls, 1);
    });

    test('a successful track change resets the failure counter', () async {
      final song1 = buildSong(1);
      final song2 = buildSong(2);
      final song3 = buildSong(3);
      final cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.playSong(song1, queue: [song1, song2, song3]);
      handler.emitError('decode failed');
      await pumpEventQueue();

      handler.emitTrackChanged(song2);
      await pumpEventQueue();
      expect(cubit.state.currentSong?.id, 2);

      handler.emitError('song 2 failed once');
      await pumpEventQueue();
      expect(handler.skipToNextCalls, 0);
      expect(cubit.state.errorMessage, 'song 2 failed once');

      handler.emitError('song 2 failed twice');
      await pumpEventQueue();
      expect(handler.skipToNextCalls, 1);
      expect(cubit.state.errorMessage, 'Skipped Song 2 (unplayable)');
    });

    test('repeat-one never auto-advances a dead track', () async {
      final song1 = buildSong(1);
      final song2 = buildSong(2);
      final cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.playSong(song1, queue: [song1, song2]);
      cubit.setStateForTesting(cubit.state.copyWith(
        playback:
            cubit.state.playback.copyWith(repeatMode: PlayerRepeatMode.one),
      ));

      handler.emitError('fail one');
      await pumpEventQueue();
      handler.emitError('fail two');
      await pumpEventQueue();

      expect(handler.skipToNextCalls, 0);
      expect(cubit.state.errorMessage, 'fail two');
    });

    test('a single-item queue has nowhere to skip to', () async {
      final song1 = buildSong(1);
      final cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.playSong(song1);

      handler.emitError('fail one');
      await pumpEventQueue();
      handler.emitError('fail two');
      await pumpEventQueue();

      expect(handler.skipToNextCalls, 0);
      expect(cubit.state.errorMessage, 'fail two');
    });

    test('repeat-off at the last item does not wrap around', () async {
      final song1 = buildSong(1);
      final song2 = buildSong(2);
      final cubit = buildCubit();
      addTearDown(cubit.close);

      await cubit.playSong(song1, queue: [song1, song2]);
      handler.emitTrackChanged(song2);
      await pumpEventQueue();
      expect(cubit.state.currentIndex, 1);

      handler.emitError('fail one');
      await pumpEventQueue();
      handler.emitError('fail two');
      await pumpEventQueue();

      expect(handler.skipToNextCalls, 0);
      expect(cubit.state.errorMessage, 'fail two');
    });
  });
}
