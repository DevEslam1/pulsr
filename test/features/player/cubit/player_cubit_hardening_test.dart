import 'dart:async';
import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/services/scrobbler_service.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/domain/usecases/toggle_favorite_usecase.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockMusicRepository extends Mock implements IMusicRepository {}

class MockToggleFavoriteUseCase extends Mock implements ToggleFavoriteUseCase {}

class MockScrobblerService extends Mock implements ScrobblerService {}

class TestPulsrAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler
    implements PulsrAudioHandler {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  double _vol = 1.0;
  @override
  double get volume => _vol;
  @override
  SongsTableData? get currentSong => null;
  @override
  int? get currentAudioSessionId => null;
  @override
  Stream<int?> get audioSessionIdStream => Stream<int?>.empty();
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

  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();

  @override
  void setCrossfadeDuration(Duration d) {
    currentCrossfadeDuration = d;
  }

  @override
  Future<void> restoreLastPlaybackSession() async {}

  @override
  Future<void> saveCurrentPositionImmediate() async {}

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
  Future<void> setDynamicsPreset(DynamicsPreset preset,
      {bool? enabled}) async {}

  @override
  Future<void> applyHeadphoneProfile(HeadphoneProfile? profile) async {}

  @override
  bool get isSpatializerEnabled => false;

  @override
  bool get isSpatializerSupported => false;

  @override
  bool get isHeadTrackerAvailable => false;

  @override
  Future<void> setSpatializerEnabled(bool enabled) async {}

  @override
  double get volumeBoost => 0.0;

  @override
  Future<void> setVolumeBoost(double value) async {}

  @override
  Future<void> resetToFlat() async {}

  @override
  Future<void> startAbComparison() async {}

  @override
  Future<void> endAbComparison() async {}

  @override
  bool get isAbComparisonActive => false;

  @override
  bool get isCrossfeedEnabled => false;
  @override
  double get crossfeedDelayUs => 350.0;
  @override
  double get crossfeedFeedDb => -9.0;
  @override
  bool get isLimiterEnabled => false;
  @override
  double get limiterThresholdDb => -0.2;
  @override
  double get limiterReleaseMs => 50.0;
  @override
  bool get isReverbEnabled => false;
  @override
  int get reverbPreset => 0;
  @override
  double get reverbWetDry => 0.20;
  @override
  double get stereoBalance => 0.0;
  @override
  bool get monoMix => false;
  @override
  bool get isSincResamplerEnabled => true;
  @override
  bool get hasOemAudio => false;
  @override
  List<String> get detectedOemEngines => const [];

  // Phase 1 DSP expansion stage surface (mirror PulsrAudioHandler)
  @override
  bool get isSaturationEnabled => false;
  @override
  double get saturationDrive => 0.0;
  @override
  double get saturationMix => 0.5;
  @override
  double get saturationTilt => 0.0;
  @override
  bool get isStereoWidthEnabled => false;
  @override
  double get stereoWidth => 1.0;
  @override
  bool get isLoudnessContourEnabled => false;
  @override
  double get loudnessContourIntensity => 0.0;
  @override
  bool get isSubCrossoverEnabled => false;
  @override
  double get subCrossoverCornerHz => 80.0;
  @override
  double get subCrossoverSlopeDbPerOct => 24.0;
  @override
  double get subCrossoverGain => 0.8;
  @override
  bool get isDynamicEqEnabled => false;
  @override
  List<DynamicEqBandConfig> get dynamicEqBands => const [];
  @override
  Future<void> setSaturation(bool enabled,
          {double? drive, double? mix, double? tilt}) async {}
  @override
  Future<void> setStereoWidth(bool enabled, {double? width}) async {}
  @override
  Future<void> setLoudnessContour(bool enabled, {double? intensity}) async {}
  @override
  Future<void> setSubCrossover(bool enabled,
          {double? cornerHz, double? slopeDbPerOct, double? gain}) async {}
  @override
  Future<void> setDynamicEq(bool enabled) async {}
  @override
  Future<void> setDynamicEqBand(int index, DynamicEqBandConfig band) async {}

  @override
  Future<void> setCrossfeed(bool enabled,
      {double? delayUs, double? feedDb}) async {}
  @override
  Future<void> setLookaheadLimiter(bool enabled,
      {double? thresholdDb, double? releaseMs, double? lookaheadMs}) async {}
  @override
  Future<void> setReverb(bool enabled, {int? preset, double? wetDry}) async {}
  @override
  Future<void> loadCustomImpulseResponse(List<double> irSamples) async {}
  @override
  Future<void> setStereoBalance(double balance) async {}
  @override
  Future<void> setMonoMix(bool mono) async {}
  @override
  Future<void> setSincResampler(bool enabled) async {}

  @override
  Future<void> toggleDynamicsBypass() async {}

  @override
  bool get isDynamicsBypassed => false;

  @override
  Future<void> setCustomFrequencies(List<double> frequencies) async {}

  @override
  Future<void> onAppPaused() async {}

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
  Future<void> loadQueue(List<SongsTableData> songs,
      {int initialIndex = 0, Duration? initialPosition}) async {}

  @override
  Stream<Duration?> get sleepTimerRemainingStream => const Stream.empty();

  @override
  Stream<String> get errorStream => const Stream.empty();

  @override
  void dispose() {
    _positionController.close();
  }

  @override
  Future<void> playSongAt(int index, {Duration? initialPosition}) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> validatePlayerState() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockMusicRepository mockRepository;
  late MockToggleFavoriteUseCase mockToggleFavorite;
  late MockScrobblerService mockScrobblerService;
  late TestPulsrAudioHandler testAudioHandler;

  final sampleSong1 = SongsTableData(
    id: 1,
    title: 'Track 1',
    artist: 'Artist 1',
    album: 'Album 1',
    durationMs: 180000,
    path: '/path/1.mp3',
    isFavorite: false,
    isMissing: false,
    isDownloaded: false,
    playCount: 0,
    lastPositionMs: 0,
    source: 'local',
  );

  final missingSong = SongsTableData(
    id: 2,
    title: 'Missing Track',
    artist: 'Artist 2',
    album: 'Album 2',
    durationMs: 200000,
    path: '/path/missing.mp3',
    isFavorite: false,
    isMissing: true,
    isDownloaded: false,
    playCount: 0,
    lastPositionMs: 0,
    source: 'local',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRepository = MockMusicRepository();
    mockToggleFavorite = MockToggleFavoriteUseCase();
    mockScrobblerService = MockScrobblerService();
    testAudioHandler = TestPulsrAudioHandler();

    when(() => mockRepository.getSongById(any()))
        .thenAnswer((_) async => right(sampleSong1));
    when(() => mockRepository.getSongsByIds(any()))
        .thenAnswer((_) async => right([sampleSong1]));
    when(() => mockScrobblerService.notifyPlaybackState(
          id: any(named: 'id'),
          artist: any(named: 'artist'),
          track: any(named: 'track'),
          album: any(named: 'album'),
          durationMs: any(named: 'durationMs'),
          positionMs: any(named: 'positionMs'),
          isPlaying: any(named: 'isPlaying'),
        )).thenAnswer((_) async {});
  });

  group('PlayerCubit Hardening Tests', () {
    test('Queue slots persist to SharedPreferences after queue operations',
        () async {
      final cubit = PlayerCubit(
        audioHandler: testAudioHandler,
        repository: mockRepository,
        toggleFavoriteUseCase: mockToggleFavorite,
        scrobblerService: mockScrobblerService,
      );

      await cubit.playSong(sampleSong1);

      // Wait for debounce timer (2s)
      await Future.delayed(const Duration(milliseconds: 2100));

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(PrefsKeys.queueSlots);
      expect(raw, isNotNull);
      final data = jsonDecode(raw!) as Map<String, dynamic>;
      expect(data['0'], isNotNull);
      expect((data['0']['songIds'] as List), contains(1));

      await cubit.close();
    });

    test('switchQueueSlot filters out missing songs', () async {
      final cubit = PlayerCubit(
        audioHandler: testAudioHandler,
        repository: mockRepository,
        toggleFavoriteUseCase: mockToggleFavorite,
        scrobblerService: mockScrobblerService,
      );

      // Populate slot 1 with missing song
      await cubit.switchQueueSlot(1);
      await cubit.playSong(missingSong);

      // Switch to slot 0, then back to slot 1
      await cubit.switchQueueSlot(0);
      await cubit.playSong(sampleSong1);

      await cubit.switchQueueSlot(1);
      // Slot 1 had only missing song, so it emits error and empty queue
      expect(cubit.state.errorMessage, equals('Queue slot is empty'));

      await cubit.close();
    });

    test('Queue size is capped at 500 tracks', () async {
      final cubit = PlayerCubit(
        audioHandler: testAudioHandler,
        repository: mockRepository,
        toggleFavoriteUseCase: mockToggleFavorite,
        scrobblerService: mockScrobblerService,
      );

      final largeList = List.generate(
        600,
        (i) => SongsTableData(
          id: i + 1,
          title: 'Track $i',
          artist: 'Artist',
          album: 'Album',
          durationMs: 100000,
          path: '/path/$i.mp3',
          isFavorite: false,
          isMissing: false,
          isDownloaded: false,
          playCount: 0,
          lastPositionMs: 0,
          source: 'local',
        ),
      );

      await cubit.playSong(largeList.first, queue: largeList);
      expect(cubit.state.queue.length, equals(500));

      await cubit.close();
    });
  });
}
