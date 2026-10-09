// test/features/player/player_playback_options_controller_test.dart
//
// Coverage for [PlayerPlaybackOptionsController]: speed/pitch guards and
// rollback, ratings, per-song overrides, EQ import/export, per-song playback
// memory, overlay toggles, sleep-timer and volume delegation.
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/per_song_eq_store.dart';
import 'package:pulsr/data/audio/per_song_playback_store.dart';
import 'package:pulsr/data/audio/per_song_volume_store.dart';
import 'package:pulsr/data/audio/sleep_timer_manager.dart';
import 'package:pulsr/data/audio/song_rating_store.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/features/player/cubit/controllers/player_playback_options_controller.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_test_support.dart';

class _MockAudioHandler extends Mock implements PulsrAudioHandler {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(DateTime(2020));
    registerFallbackValue(flatPreset);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  PlayerPlaybackOptionsController make(
    _MockAudioHandler handler, {
    PlayerState Function()? getState,
    void Function(PlayerState)? emit,
    PerSongPlaybackStore? playbackStore,
    PerSongVolumeStore? volumeStore,
    PerSongEqStore? eqStore,
    SongRatingStore? ratingStore,
    bool Function(String feature, {bool showError})? guardDsp,
    String? Function()? rateGuard,
    bool Function()? isClosed,
  }) {
    return PlayerPlaybackOptionsController(
      audioHandler: handler,
      perSongPlaybackStore: playbackStore,
      perSongVolumeStore: volumeStore,
      perSongEqStore: eqStore,
      songRatingStore: ratingStore,
      guardDsp: guardDsp,
      playbackRateBlockedReason: rateGuard,
      getState: getState ?? () => const PlayerState(),
      emit: emit ?? (_) {},
      isClosed: isClosed ?? () => false,
    );
  }

  test('setPlaybackSpeed clamps to range, persists and records per-song memory',
      () async {
    final handler = _MockAudioHandler();
    when(() => handler.minPlaybackSpeed).thenReturn(0.5);
    when(() => handler.maxPlaybackSpeed).thenReturn(3.0);
    when(() => handler.setSpeed(any())).thenAnswer((_) async {});

    final store = PerSongPlaybackStore();
    var state = PlayerState(playback: PlaybackSlice(currentSong: buildSong(1)));
    final controller = make(
      handler,
      getState: () => state,
      emit: (s) => state = s,
      playbackStore: store,
    );

    await controller.setPlaybackSpeed(9.0);
    expect(state.playbackSpeed, 3.0);
    expect(store.getSpeed('1'), closeTo(3.0, 1e-9));
    verify(() => handler.setSpeed(3.0)).called(1);

    // No current song still changes speed but skips memory persistence.
    final noSong = make(
      handler,
      getState: () => const PlayerState(),
      emit: (_) {},
      playbackStore: PerSongPlaybackStore(),
    );
    await noSong.setPlaybackSpeed(1.5);
  });

  test('setPlaybackSpeed is refused by the bit-perfect rate guard', () async {
    final handler = _MockAudioHandler();
    when(() => handler.minPlaybackSpeed).thenReturn(0.5);
    when(() => handler.maxPlaybackSpeed).thenReturn(3.0);

    var state = const PlayerState();
    final controller = make(
      handler,
      getState: () => state,
      emit: (s) => state = s,
      rateGuard: () => 'Bit-Perfect bypass is ON',
    );

    await controller.setPlaybackSpeed(1.5);
    expect(state.playbackSpeed, 1.0);
    expect(state.playback.errorMessage, contains('Bit-Perfect bypass'));
    verifyNever(() => handler.setSpeed(any()));
  });

  test('setPlaybackSpeed rolls back and reports an error when the engine throws',
      () async {
    final handler = _MockAudioHandler();
    when(() => handler.minPlaybackSpeed).thenReturn(0.5);
    when(() => handler.maxPlaybackSpeed).thenReturn(3.0);
    when(() => handler.setSpeed(any())).thenThrow(Exception('boom'));

    var state = PlayerState(
      playback: const PlaybackSlice(playbackSpeed: 1.25),
    );
    final controller = make(handler, getState: () => state, emit: (s) => state = s);

    await controller.setPlaybackSpeed(1.5);
    expect(state.playbackSpeed, 1.25);
    expect(state.playback.errorMessage, 'Speed change failed');
  });

  test('setPlaybackPitch persists and rolls back on failure', () async {
    final handler = _MockAudioHandler();
    when(() => handler.setPitch(any())).thenAnswer((_) async {});

    final store = PerSongPlaybackStore();
    var state = PlayerState(playback: PlaybackSlice(currentSong: buildSong(2)));
    final controller =
        make(handler, getState: () => state, emit: (s) => state = s, playbackStore: store);

    await controller.setPlaybackPitch(1.4);
    expect(state.playbackPitch, 1.4);
    expect(store.getPitch('2'), closeTo(1.4, 1e-9));

    when(() => handler.setPitch(any())).thenThrow(Exception('boom'));
    await controller.setPlaybackPitch(0.6);
    expect(state.playback.errorMessage, 'Pitch change failed');
  });

  test('setSongRating clamps, persists, and only emits for the current song',
      () async {
    final handler = _MockAudioHandler();
    final ratingStore = SongRatingStore();
    var state = PlayerState(playback: PlaybackSlice(currentSong: buildSong(3)));
    final controller = make(
      handler,
      getState: () => state,
      emit: (s) => state = s,
      ratingStore: ratingStore,
    );

    await controller.setSongRating(3, 99);
    expect(state.currentSongRating, 5);
    expect(ratingStore.getRating('3'), 5);

    // A rating for a different song persists but does not touch state.
    state = state.copyWith(
        playback: state.playback.copyWith(currentSongRating: 5));
    await controller.setSongRating(99, 2);
    expect(state.currentSongRating, 5);
    expect(ratingStore.getRating('99'), 2);
  });

  test('setRating targets the current song; null song is a no-op', () async {
    final handler = _MockAudioHandler();
    final ratingStore = SongRatingStore();
    var state = PlayerState(playback: PlaybackSlice(currentSong: buildSong(4)));
    final controller = make(
      handler,
      getState: () => state,
      emit: (s) => state = s,
      ratingStore: ratingStore,
    );

    await controller.setRating(3);
    expect(state.currentSongRating, 3);

    final noSong = make(handler, ratingStore: SongRatingStore());
    await noSong.setRating(4); // no current song -> no throw
  });

  test('checkDspGuard defaults true and delegates when a guard is provided', () {
    final handler = _MockAudioHandler();
    expect(make(handler).checkDspGuard('feature'), isTrue);

    final guarded = make(
      handler,
      guardDsp: (feature, {bool showError = true}) =>
          feature == 'allowed' && showError,
    );
    expect(guarded.checkDspGuard('allowed'), isTrue);
    expect(guarded.checkDspGuard('denied'), isFalse);
  });

  test('importEqPreset honours the DSP guard, success and closed states',
      () async {
    final handler = _MockAudioHandler();
    when(() => handler.importPresetFromJson(any())).thenAnswer((_) async => true);
    const preset = EqPreset(name: 'Imported', gains: [1, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    when(() => handler.currentPreset).thenReturn(preset);

    var state = const PlayerState();
    final guarded = make(
      handler,
      getState: () => state,
      emit: (s) => state = s,
      guardDsp: (f, {bool showError = true}) => false,
    );
    expect(await guarded.importEqPreset('{}'), isFalse);
    verifyNever(() => handler.importPresetFromJson(any()));

    final controller = make(handler, getState: () => state, emit: (s) => state = s);
    expect(await controller.importEqPreset('{}'), isTrue);
    expect(state.eqPreset, preset);

    final closed = make(
      handler,
      getState: () => state,
      emit: (s) => state = s,
      isClosed: () => true,
    );
    expect(await closed.importEqPreset('{}'), isTrue);
    expect(state.eqPreset, preset); // emit skipped while closed
  });

  test('exportCurrentEqPreset delegates to the handler', () {
    final handler = _MockAudioHandler();
    const state = PlayerState();
    when(() => handler.exportPresetToJson(any())).thenReturn('{"ok":true}');
    expect(make(handler, getState: () => state).exportCurrentEqPreset(),
        '{"ok":true}');
  });

  test('setSongEqOverride dispatches across int, String, null and other',
      () async {
    final handler = _MockAudioHandler();
    final eqStore = PerSongEqStore();
    var state = PlayerState(playback: PlaybackSlice(currentSong: buildSong(5)));
    final controller =
        make(handler, getState: () => state, emit: (s) => state = s, eqStore: eqStore);

    await controller.setSongEqOverride(5, 'Bass'); // int branch
    expect(state.currentSongEqOverride, 'Bass');

    await controller.setSongEqOverride('Treble'); // String branch
    expect(state.currentSongEqOverride, 'Treble');

    await controller.setSongEqOverride(null); // null + null -> clear current
    expect(state.currentSongEqOverride, isNull);

    await controller.setSongEqOverride(3.14); // other -> no-op
    expect(state.currentSongEqOverride, isNull);

    // setCurrentSongEqOverride with no song is a no-op.
    final noSong = make(handler, eqStore: PerSongEqStore());
    await noSong.setCurrentSongEqOverride('X');
  });

  test('setSongEqOverrideById persists and emits only for the current song',
      () async {
    final handler = _MockAudioHandler();
    final eqStore = PerSongEqStore();
    var state = PlayerState(playback: PlaybackSlice(currentSong: buildSong(6)));
    final controller =
        make(handler, getState: () => state, emit: (s) => state = s, eqStore: eqStore);

    await controller.setSongEqOverrideById(6, 'Vocal');
    expect(state.currentSongEqOverride, 'Vocal');
    expect(eqStore.getPresetForTrack('6'), 'Vocal');

    await controller.setSongEqOverrideById(7, 'Other');
    expect(state.currentSongEqOverride, 'Vocal'); // unchanged
    expect(eqStore.getPresetForTrack('7'), 'Other');
  });

  test('setSongVolumeOverride clamps and emits for the current song', () async {
    final handler = _MockAudioHandler();
    final volumeStore = PerSongVolumeStore();
    var state = PlayerState(playback: PlaybackSlice(currentSong: buildSong(7)));
    final controller = make(
      handler,
      getState: () => state,
      emit: (s) => state = s,
      volumeStore: volumeStore,
    );

    await controller.setSongVolumeOverride(7, 99.0);
    expect(state.currentSongVolumeOverrideDb, 24.0);

    // Overload resolves the id (explicit and current).
    await controller.setSongVolumeOverrideDb(-99.0, songId: 7);
    expect(state.currentSongVolumeOverrideDb, -24.0);
    await controller.setSongVolumeOverrideDb(3.0);
    expect(state.currentSongVolumeOverrideDb, 3.0);

    // No id at all is a no-op.
    final noSong = make(handler, volumeStore: PerSongVolumeStore());
    await noSong.setSongVolumeOverrideDb(1.0);
  });

  test('applyPerSongPlaybackMemory restores speed, pitch, volume and EQ',
      () async {
    final handler = _MockAudioHandler();
    when(() => handler.setSpeed(any())).thenAnswer((_) async {});
    when(() => handler.setPitch(any())).thenAnswer((_) async {});

    final playbackStore = PerSongPlaybackStore();
    await playbackStore.setSpeed('8', 1.5);
    await playbackStore.setPitch('8', 0.75);
    final volumeStore = PerSongVolumeStore();
    await volumeStore.setGainDbForTrack('8', -4.0);
    final eqStore = PerSongEqStore();
    await eqStore.setPresetForTrack('8', 'Bass');

    var state = PlayerState(playback: PlaybackSlice(currentSong: buildSong(8)));
    final controller = make(
      handler,
      getState: () => state,
      emit: (s) => state = s,
      playbackStore: playbackStore,
      volumeStore: volumeStore,
      eqStore: eqStore,
    );

    await controller.applyPerSongPlaybackMemory(buildSong(8));
    expect(state.playbackSpeed, 1.5);
    expect(state.playbackPitch, 0.75);
    expect(state.currentSongVolumeOverrideDb, -4.0);
    expect(state.currentSongEqOverride, 'Bass');
  });

  test('applyPerSongPlaybackMemory bails on quran mode, mismatch and closed',
      () async {
    final handler = _MockAudioHandler();
    when(() => handler.setSpeed(any())).thenAnswer((_) async {});

    final playbackStore = PerSongPlaybackStore();
    await playbackStore.setSpeed('9', 1.5);

    var state = PlayerState(
      playback: PlaybackSlice(currentSong: buildSong(9)),
      dsp: const DspSlice(isQuranModeEnabled: true),
    );
    final quran = make(
      handler,
      getState: () => state,
      emit: (s) => state = s,
      playbackStore: playbackStore,
    );
    await quran.applyPerSongPlaybackMemory(buildSong(9));
    expect(state.playbackSpeed, 1.0);

    final mismatch = make(
      handler,
      getState: () => state,
      emit: (s) => state = s,
      playbackStore: playbackStore,
    );
    await mismatch.applyPerSongPlaybackMemory(buildSong(999));
    expect(state.playbackSpeed, 1.0);

    final closed = make(
      handler,
      getState: () => state,
      emit: (s) => state = s,
      playbackStore: playbackStore,
      isClosed: () => true,
    );
    await closed.applyPerSongPlaybackMemory(buildSong(9));
    expect(state.playbackSpeed, 1.0);
  });

  test('applyPerSongPlaybackMemory swallows engine failures and keeps old values',
      () async {
    final handler = _MockAudioHandler();
    when(() => handler.setSpeed(any())).thenThrow(Exception('boom'));
    when(() => handler.setPitch(any())).thenThrow(Exception('boom'));

    final playbackStore = PerSongPlaybackStore();
    await playbackStore.setSpeed('10', 1.5);
    await playbackStore.setPitch('10', 0.75);

    var state = PlayerState(playback: PlaybackSlice(currentSong: buildSong(10)));
    final controller = make(
      handler,
      getState: () => state,
      emit: (s) => state = s,
      playbackStore: playbackStore,
    );

    await controller.applyPerSongPlaybackMemory(buildSong(10));
    expect(state.playbackSpeed, 1.0);
    expect(state.playbackPitch, 1.0);
  });

  test('overlay toggles, reset and playback option setters emit', () {
    final handler = _MockAudioHandler();
    var state = const PlayerState();
    final controller =
        make(handler, getState: () => state, emit: (s) => state = s);

    controller.toggleLyrics();
    expect(state.isLyricsVisible, isTrue);
    expect(state.isQueueVisible, isFalse);

    controller.toggleQueue();
    expect(state.isQueueVisible, isTrue);
    expect(state.isLyricsVisible, isFalse);

    controller.resetOverlayViews();
    expect(state.isLyricsVisible, isFalse);
    expect(state.isQueueVisible, isFalse);

    // reset on an already-clear state is a no-op branch.
    controller.resetOverlayViews();

    controller.setExpanded(true);
    expect(state.isExpanded, isTrue);
    controller.setTrackDelayMs(250);
    expect(state.trackDelayMs, 250);
    controller.setSilenceSkipSensitivity(3);
    expect(state.silenceSkipSensitivity, 3);

    final song = buildSong(11);
    when(() => handler.setTrackBpm(song, 128.0)).thenAnswer((_) async => true);
    controller.setTrackBpm(song, 128.0);
  });

  test('sleep timer delegation arms and cancels', () {
    final handler = _MockAudioHandler();
    when(() => handler.startSleepTimer(any())).thenAnswer((_) {});
    when(() => handler.startAbsoluteSleepTimer(any())).thenAnswer((_) {});
    when(() => handler.startEndOfTrackTimer()).thenAnswer((_) {});
    when(() => handler.startAfterNTracksTimer(any())).thenAnswer((_) {});
    when(() => handler.startEndOfQueueTimer()).thenAnswer((_) {});
    when(() => handler.cancelSleepTimer()).thenAnswer((_) {});
    when(() => handler.sleepTimerRemainingTracks).thenReturn(2);
    when(() => handler.sleepTimerMode).thenReturn(SleepTimerMode.endOfQueue);
    when(() => handler.sleepTimerRemainingTracksStream)
        .thenAnswer((_) => const Stream<int?>.empty());

    var state = const PlayerState();
    final controller =
        make(handler, getState: () => state, emit: (s) => state = s);

    controller.startSleepTimer(30);
    expect(state.sleepTimerRemaining, const Duration(minutes: 30));

    controller.startSleepTimer(0); // ignored
    controller.startAbsoluteSleepTimer(
        DateTime.now().subtract(const Duration(minutes: 5)));
    controller.startEndOfTrackTimer();
    controller.startAfterNTracksTimer(2);
    expect(state.sleepTimerRemainingTracks, 2);
    controller.startEndOfQueueTimer();
    controller.cancelSleepTimer();
    expect(state.sleepTimerRemaining, isNull);

    expect(controller.sleepTimerRemainingTracks, 2);
    expect(controller.sleepTimerMode, SleepTimerMode.endOfQueue);
    expect(controller.isEndOfQueueSleepTimer, isTrue);
    expect(controller.sleepTimerRemainingTracksStream, isNotNull);
  });

  test('volume and mute delegation', () async {
    final handler = _MockAudioHandler();
    when(() => handler.volume).thenReturn(0.5);
    when(() => handler.setVolume(any())).thenAnswer((_) async {});

    final controller = make(handler);
    expect(controller.isMuted, isFalse);

    await controller.setVolume(0.3);
    verify(() => handler.setVolume(0.3)).called(1);

    await controller.adjustVolume(-0.1);
    verify(() => handler.setVolume(0.4)).called(1);

    await controller.toggleMute();
    expect(controller.isMuted, isTrue);
    await controller.toggleMute();
    expect(controller.isMuted, isFalse);
  });

  test('volume failures report an error on state', () async {
    final handler = _MockAudioHandler();
    when(() => handler.setVolume(any())).thenThrow(Exception('boom'));

    var state = const PlayerState();
    final controller =
        make(handler, getState: () => state, emit: (s) => state = s);
    await controller.setVolume(0.2);
    expect(state.errorMessage, 'Volume change failed');
  });

  test('min/max speed and pitch accessors delegate', () {
    final handler = _MockAudioHandler();
    when(() => handler.minPlaybackSpeed).thenReturn(0.25);
    when(() => handler.maxPlaybackSpeed).thenReturn(4.0);
    final controller = make(handler);
    expect(controller.minPlaybackSpeed, 0.25);
    expect(controller.maxPlaybackSpeed, 4.0);
    expect(controller.minPlaybackPitch, 0.5);
    expect(controller.maxPlaybackPitch, 2.0);
    expect(controller.isClosed, isFalse);
    controller.dispose();
  });
}
