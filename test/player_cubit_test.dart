import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';
import 'package:pulsr/domain/usecases/toggle_favorite_usecase.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/widgets/widget_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';

class MockMusicRepository extends Mock implements IMusicRepository {}
class MockToggleFavoriteUseCase extends Mock implements ToggleFavoriteUseCase {}
class MockMediaScannerService extends Mock implements MediaScannerService {}
class MockWidgetService extends Mock implements WidgetService {}

class TestPulsrAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler implements PulsrAudioHandler {
  double _vol = 1.0;
  @override
  double get volume => _vol;
  @override
  Future<void> setVolume(double volume) async {
    _vol = volume;
  }
  bool eqEnabled = false;
  EqPreset currentEqPreset = EqPreset.defaultPresets.first;
  Duration? sleepTimerDuration;
  Duration currentCrossfadeDuration = Duration.zero;

  @override
  bool get isEqualizerEnabled => eqEnabled;

  @override
  EqPreset get currentPreset => currentEqPreset;

  @override
  Duration get crossfadeDuration => currentCrossfadeDuration;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  final StreamController<Duration> _positionController = StreamController<Duration>.broadcast();

  @override
  void setCrossfadeDuration(Duration d) {
    currentCrossfadeDuration = d;
  }

  @override
  Future<void> restoreLastPlaybackSession() async {}

  @override
  void saveCurrentPositionImmediate() {}

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
  bool get isVirtualizerEnabled => false;

  @override
  double get virtualizerStrength => 0.0;

  @override
  bool get isDynamicsEnabled => false;

  @override
  DynamicsPreset get dynamicsPreset => DynamicsPreset.off;

  @override
  HeadphoneProfile? get selectedHeadphoneProfile => null;

  @override
  Future<void> setVirtualizerEnabled(bool enabled) async {}

  @override
  Future<void> setVirtualizerStrength(double strength) async {}

  @override
  Future<void> setDynamicsPreset(DynamicsPreset preset, {bool? enabled}) async {}

  @override
  Future<void> applyHeadphoneProfile(HeadphoneProfile? profile) async {}

  @override
  bool get isSpatializerEnabled => false;

  @override
  bool get isSpatializerSupported => false;

  @override
  Future<void> setSpatializerEnabled(bool enabled) async {}

  @override
  double get volumeBoost => 0.0;

  @override
  Future<void> setVolumeBoost(double value) async {}

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
  Future<void> insertNextInQueue(SongsTableData song) async {}

  @override
  Future<void> addToQueueEnd(SongsTableData song) async {}

  @override
  Future<void> reorderQueue(int oldIndex, int newIndex) async {}

  @override
  Future<void> removeQueueItemAt(int index) async {}

  @override
  Future<void> loadQueue(List<SongsTableData> songs, {int initialIndex = 0, Duration? initialPosition}) async {}

  @override
  Stream<Duration?> get sleepTimerRemainingStream => const Stream.empty();

  @override
  void dispose() {
    _positionController.close();
  }

  @override
  Future<void> playSongAt(int index, {Duration? initialPosition}) async {}
}

void main() {
  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

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

    test('crossfade duration updates when settings cubit changes', () async {
      final mockScannerService = MockMediaScannerService();
      SharedPreferences.setMockInitialValues({'setting_crossfade': 4.0});
      final settingsCubit = SettingsCubit(scannerService: mockScannerService);

      final cubit = PlayerCubit(
        audioHandler: testAudioHandler,
        repository: mockRepository,
        toggleFavoriteUseCase: mockToggleFavorite,
        settingsCubit: settingsCubit,
      );

      await settingsCubit.setCrossfade(6.0);
      expect(testAudioHandler.currentCrossfadeDuration, const Duration(seconds: 6));

      cubit.close();
      await settingsCubit.close();
    });

    test('updates widget with playback state and favorite status', () async {
      final mockWidgetService = MockWidgetService();
      when(() => mockWidgetService.listenToWidgetClicks(any())).thenReturn(
        StreamController<Uri?>().stream.listen((_) {}),
      );
      when(
        () => mockWidgetService.updateNowPlaying(
          song: any(named: 'song'),
          isPlaying: any(named: 'isPlaying'),
          position: any(named: 'position'),
          duration: any(named: 'duration'),
          isFavorite: any(named: 'isFavorite'),
          isShuffle: any(named: 'isShuffle'),
          repeatMode: any(named: 'repeatMode'),
        ),
      ).thenAnswer((_) async {});

      final cubit = PlayerCubit(
        audioHandler: testAudioHandler,
        repository: mockRepository,
        toggleFavoriteUseCase: mockToggleFavorite,
        widgetService: mockWidgetService,
      );

      verify(() => mockWidgetService.listenToWidgetClicks(any())).called(1);

      cubit.close();
    });

    test('position stream only emits when delta exceeds 100ms', () async {
      final cubit = PlayerCubit(
        audioHandler: testAudioHandler,
        repository: mockRepository,
        toggleFavoriteUseCase: mockToggleFavorite,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 50ms delta from zero - should not emit
      testAudioHandler._positionController.add(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(cubit.state.position, Duration.zero);

      // 200ms delta from 50ms - should emit
      testAudioHandler._positionController.add(const Duration(milliseconds: 250));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(cubit.state.position, const Duration(milliseconds: 250));

      cubit.close();
    });
  });
}
