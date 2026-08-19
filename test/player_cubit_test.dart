// test/player_cubit_test.dart
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/repositories/music_repository.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/usecases/toggle_favorite_usecase.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';

class MockMusicRepository extends Mock implements MusicRepository {}
class MockToggleFavoriteUseCase extends Mock implements ToggleFavoriteUseCase {}

class TestPulsrAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler implements PulsrAudioHandler {
  bool eqEnabled = false;
  EqPreset currentEqPreset = EqPreset.defaultPresets.first;
  Duration? sleepTimerDuration;

  @override
  bool get isEqualizerEnabled => eqEnabled;

  @override
  EqPreset get currentPreset => currentEqPreset;

  @override
  Future<void> setEqualizerEnabled(bool enabled) async {
    eqEnabled = enabled;
  }

  @override
  Future<void> applyPreset(EqPreset preset) async {
    currentEqPreset = preset;
  }

  @override
  Future<void> setBandGain(int bandIndex, double gainDb) async {}

  @override
  Future<void> setBassBoost(double amount) async {}

  @override
  void startSleepTimer(Duration duration, {bool fadeOut = true}) {
    sleepTimerDuration = duration;
  }

  @override
  void startAbsoluteSleepTimer(DateTime stopTime, {bool fadeOut = true}) {
    sleepTimerDuration = stopTime.difference(DateTime.now());
  }

  @override
  void cancelSleepTimer() {
    sleepTimerDuration = null;
  }

  @override
  Future<void> playNext(dynamic song) async {}

  @override
  Future<void> addToQueue(dynamic song) async {}

  @override
  Future<void> reorderQueue(int oldIndex, int newIndex) async {}

  @override
  Future<void> removeQueueItemAt(int index) async {}

  @override
  Future<void> loadQueue(List<dynamic> songs, {int initialIndex = 0, Duration? initialPosition}) async {}

  @override
  Future<void> playSongAt(int index) async {}
}

void main() {
  late TestPulsrAudioHandler testAudioHandler;
  late MockMusicRepository mockRepository;
  late MockToggleFavoriteUseCase mockToggleFavorite;

  setUp(() {
    testAudioHandler = TestPulsrAudioHandler();
    mockRepository = MockMusicRepository();
    mockToggleFavorite = MockToggleFavoriteUseCase();
  });

  group('PlayerCubit', () {
    test('initial state defaults are correct', () {
      final cubit = PlayerCubit(
        audioHandler: testAudioHandler,
        repository: mockRepository,
        toggleFavoriteUseCase: mockToggleFavorite,
      );

      expect(cubit.state.isPlaying, false);
      expect(cubit.state.isShuffle, false);
      expect(cubit.state.repeatMode, PlayerRepeatMode.off);
      expect(cubit.state.activeQueueSlot, 0);
      expect(cubit.state.isLyricsVisible, false);
      expect(cubit.state.isQueueVisible, false);

      cubit.close();
    });

    test('equalizer enabling and preset apply updates state and audio handler', () async {
      final cubit = PlayerCubit(
        audioHandler: testAudioHandler,
        repository: mockRepository,
        toggleFavoriteUseCase: mockToggleFavorite,
      );

      await cubit.setEqualizerEnabled(true);
      expect(cubit.state.isEqEnabled, true);
      expect(testAudioHandler.eqEnabled, true);

      const rockPreset = EqPreset(name: 'Rock', gains: [4.5, 2.5, -1.0, 2.0, 4.0], bassBoost: 0.2);
      await cubit.applyPreset(rockPreset);
      expect(cubit.state.eqPreset.name, 'Rock');
      expect(testAudioHandler.currentEqPreset.name, 'Rock');

      cubit.close();
    });

    test('sleep timer starts and cancels properly', () {
      final cubit = PlayerCubit(
        audioHandler: testAudioHandler,
        repository: mockRepository,
        toggleFavoriteUseCase: mockToggleFavorite,
      );

      cubit.startSleepTimer(30);
      expect(cubit.state.sleepTimerRemaining, const Duration(minutes: 30));
      expect(testAudioHandler.sleepTimerDuration, const Duration(minutes: 30));

      cubit.cancelSleepTimer();
      expect(cubit.state.sleepTimerRemaining, isNull);
      expect(testAudioHandler.sleepTimerDuration, isNull);

      cubit.close();
    });

    test('toggleLyricsVisibility toggles lyrics and closes queue', () {
      final cubit = PlayerCubit(
        audioHandler: testAudioHandler,
        repository: mockRepository,
        toggleFavoriteUseCase: mockToggleFavorite,
      );

      cubit.toggleLyricsVisibility();
      expect(cubit.state.isLyricsVisible, true);
      expect(cubit.state.isQueueVisible, false);

      cubit.toggleLyricsVisibility();
      expect(cubit.state.isLyricsVisible, false);

      cubit.close();
    });
  });
}
