import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rxdart/rxdart.dart';
import 'package:pulsr/core/telemetry/clock.dart';
import 'package:pulsr/core/telemetry/playback_latency_tracker.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';
import 'package:pulsr/domain/usecases/toggle_favorite_usecase.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/home_widget/widget_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';

class MockMusicRepository extends Mock implements IMusicRepository {}

class MockToggleFavoriteUseCase extends Mock implements ToggleFavoriteUseCase {}

class MockMediaScannerService extends Mock implements MediaScannerService {}

class MockWidgetService extends Mock implements WidgetService {}

class TestPulsrAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler
    implements PulsrAudioHandler {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  double _vol = 1.0;
  int setVolumeCallCount = 0;
  @override
  double get volume => _vol;
  @override
  SongsTableData? get currentSong => null;
  @override
  int? get currentAudioSessionId => null;
  @override
  Future<void> setVolume(double volume) async {
    _vol = volume;
    setVolumeCallCount += 1;
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

  final StreamController<MediaItem?> _mediaItemController =
      StreamController<MediaItem?>.broadcast();
  @override
  BehaviorSubject<MediaItem?> get mediaItem =>
      BehaviorSubject<MediaItem?>.seeded(null)
        ..addStream(_mediaItemController.stream);

  final StreamController<List<MediaItem>> _queueController =
      StreamController<List<MediaItem>>.broadcast();
  @override
  BehaviorSubject<List<MediaItem>> get queue =>
      BehaviorSubject<List<MediaItem>>.seeded([])
        ..addStream(_queueController.stream);

  final StreamController<PlaybackState> _playbackStateController =
      StreamController<PlaybackState>.broadcast();
  @override
  BehaviorSubject<PlaybackState> get playbackState =>
      BehaviorSubject<PlaybackState>.seeded(PlaybackState())
        ..addStream(_playbackStateController.stream);

  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  @override
  Stream<String> get errorStream => _errorController.stream;

  final StreamController<Duration?> _sleepTimerController =
      StreamController<Duration?>.broadcast();
  @override
  Stream<Duration?> get sleepTimerRemainingStream =>
      _sleepTimerController.stream;

  final StreamController<int?> _audioSessionIdController =
      StreamController<int?>.broadcast();
  @override
  Stream<int?> get audioSessionIdStream => _audioSessionIdController.stream;

  final StreamController<SongsTableData> _onTrackChangedController =
      StreamController<SongsTableData>.broadcast();
  @override
  Stream<SongsTableData> get onTrackChanged => _onTrackChangedController.stream;

  void emitTrackChanged(SongsTableData song) {
    _onTrackChangedController.add(song);
  }

  void emitQueue(List<MediaItem> items) {
    _queueController.add(items);
  }

  void emitMediaItem(MediaItem? item) {
    _mediaItemController.add(item);
  }

  void emitPlaybackState(PlaybackState state) {
    _playbackStateController.add(state);
  }

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
  Future<void> setDynamicsPreset(
    DynamicsPreset preset, {
    bool? enabled,
  }) async {}

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
  bool persistedSaturationEnabled = false;

  @override
  bool get isSaturationEnabled => persistedSaturationEnabled;
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
  Future<void> setSaturation(
    bool enabled, {
    double? drive,
    double? mix,
    double? tilt,
  }) async {}
  @override
  Future<void> setStereoWidth(bool enabled, {double? width}) async {}
  @override
  Future<void> setLoudnessContour(bool enabled, {double? intensity}) async {}
  @override
  Future<void> setSubCrossover(
    bool enabled, {
    double? cornerHz,
    double? slopeDbPerOct,
    double? gain,
  }) async {}
  @override
  Future<void> setDynamicEq(bool enabled) async {}
  @override
  Future<void> setDynamicEqBand(int index, DynamicEqBandConfig band) async {}

  Completer<void>? readyGate;
  @override
  Future<void> get effectsReady => readyGate?.future ?? Future<void>.value();

  @override
  Future<void> setCrossfeed(
    bool enabled, {
    double? delayUs,
    double? feedDb,
  }) async {}
  @override
  Future<void> setLookaheadLimiter(
    bool enabled, {
    double? thresholdDb,
    double? releaseMs,
    double? lookaheadMs,
  }) async {}
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
  Future<void> set32BandMode(bool enabled) async {}

  @override
  Future<void> switchComparisonSlot(ComparisonSlot slot) async {}

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
  void startEndOfTrackTimer({bool fadeOut = true}) {
    sleepTimerDuration = const Duration(minutes: 1);
  }

  @override
  void startAfterNTracksTimer(int trackCount, {bool fadeOut = true}) {
    sleepTimerDuration = Duration(minutes: trackCount * 3);
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
  Future<void> loadQueue(
    List<SongsTableData> songs, {
    int initialIndex = 0,
    Duration? initialPosition,
  }) async {}

  @override
  void dispose() {
    _positionController.close();
    _mediaItemController.close();
    _queueController.close();
    _playbackStateController.close();
    _errorController.close();
    _sleepTimerController.close();
    _audioSessionIdController.close();
  }

  @override
  Future<void> playSongAt(int index, {Duration? initialPosition}) async {}

  @override
  Future<void> validatePlayerState() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> skipToNext() async {}

  @override
  Future<void> skipToPrevious() async {}

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {}

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

    test('TTFA playing mark only fires when ExoPlayer is ready AND playing, '
        'never while loading', () async {
      final tracker = PlaybackLatencyTracker.withClock(const SystemClock());
      final cubit = PlayerCubit(
        audioHandler: testAudioHandler,
        repository: mockRepository,
        toggleFavoriteUseCase: mockToggleFavorite,
        latencyTracker: tracker,
      );
      tracker.start(videoId: 'gateVid');

      // Broadcast a "playing" state while still loading — the tracker session
      // must NOT be completed (this was the premature-mark bug).
      testAudioHandler._playbackStateController.add(
        PlaybackState(
          processingState: AudioProcessingState.loading,
          playing: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        tracker.hasActiveSession,
        isTrue,
        reason: 'loading must not mark playing',
      );
      expect(tracker.lastReport, isNull);

      // Now ready + playing — real audible start completes the session.
      testAudioHandler._playbackStateController.add(
        PlaybackState(
          processingState: AudioProcessingState.ready,
          playing: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(tracker.lastReport, isNotNull);
      expect(tracker.lastReport!.success, isTrue);
      expect(
        tracker.lastReport!.stageOffsets.containsKey(PlaybackStage.playing),
        isTrue,
      );

      await cubit.close();
      tracker.dispose();
    });

    test(
      'equalizer enabling and preset apply updates state and audio handler',
      () async {
        final cubit = PlayerCubit(
          audioHandler: testAudioHandler,
          repository: mockRepository,
          toggleFavoriteUseCase: mockToggleFavorite,
        );

        await cubit.setEqualizerEnabled(true);
        expect(cubit.state.isEqEnabled, true);
        expect(testAudioHandler.eqEnabled, true);

        const rockPreset = EqPreset(
          name: 'Rock',
          gains: [4.5, 2.5, -1.0, 2.0, 4.0],
          bassBoost: 0.2,
        );
        await cubit.applyPreset(rockPreset);
        expect(cubit.state.eqPreset.name, 'Rock');
        expect(testAudioHandler.currentEqPreset.name, 'Rock');

        await cubit.close();
      },
    );

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
      await pumpEventQueue();
      expect(
        testAudioHandler.currentCrossfadeDuration,
        const Duration(seconds: 6),
      );

      await cubit.close();
      await settingsCubit.close();
    });

    test('updates widget with playback state and favorite status', () async {
      final mockWidgetService = MockWidgetService();
      when(
        () => mockWidgetService.listenToWidgetClicks(any()),
      ).thenReturn(StreamController<Uri?>().stream.listen((_) {}));
      when(
        () => mockWidgetService.updateNowPlaying(
          song: any(named: 'song'),
          isPlaying: any(named: 'isPlaying'),
          position: any(named: 'position'),
          duration: any(named: 'duration'),
          isFavorite: any(named: 'isFavorite'),
          isShuffle: any(named: 'isShuffle'),
          repeatMode: any(named: 'repeatMode'),
          nextQueueTitles: any(named: 'nextQueueTitles'),
        ),
      ).thenAnswer((_) async {});

      final cubit = PlayerCubit(
        audioHandler: testAudioHandler,
        repository: mockRepository,
        toggleFavoriteUseCase: mockToggleFavorite,
        widgetService: mockWidgetService,
      );

      verify(() => mockWidgetService.listenToWidgetClicks(any())).called(1);

      await cubit.close();
    });

    test('position stream updates state continuously', () async {
      final cubit = PlayerCubit(
        audioHandler: testAudioHandler,
        repository: mockRepository,
        toggleFavoriteUseCase: mockToggleFavorite,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      testAudioHandler._positionController.add(
        const Duration(milliseconds: 100),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(cubit.state.position, const Duration(milliseconds: 100));

      testAudioHandler._positionController.add(
        const Duration(milliseconds: 300),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(cubit.state.position, const Duration(milliseconds: 300));

      await cubit.close();
    });

    test(
      '[E4] close() during playback: no throw, 0 active subscriptions',
      () async {
        final cubit = PlayerCubit(
          audioHandler: testAudioHandler,
          repository: mockRepository,
          toggleFavoriteUseCase: mockToggleFavorite,
        );
        expect(cubit.activeSubscriptionCount, greaterThan(0));

        // Simulate close during active state
        await expectLater(cubit.close(), completes);
        expect(cubit.activeSubscriptionCount, equals(0));
        expect(cubit.isClosed, isTrue);
      },
    );

    test(
      '[E4] 1000 position ticks in 10s -> throttled emissions to seek-bar selector, 0 to metadata selector',
      () async {
        final cubit = PlayerCubit(
          audioHandler: testAudioHandler,
          repository: mockRepository,
          toggleFavoriteUseCase: mockToggleFavorite,
        );

        final song = SongsTableData(
          id: 101,
          title: 'Throttled Song',
          artist: 'Artist',
          album: 'Album',
          durationMs: 300000,
          path: '/path/101.mp3',
          isFavorite: false,
          isMissing: false,
          isDownloaded: false,
          playCount: 0,
          lastPositionMs: 0,
          source: SongSource.local,
        );
        await cubit.playSong(song);

        int seekBarEmissions = 0;
        int metadataEmissions = 0;

        // Selectors
        final posSub = cubit.stream
            .map((s) => s.position)
            .distinct()
            .listen((_) => seekBarEmissions++);

        final initialMeta = (
          cubit.state.currentSong?.id,
          cubit.state.isPlaying,
          cubit.state.queue.length,
        );
        final metaSub = cubit.stream
            .map((s) => (s.currentSong?.id, s.isPlaying, s.queue.length))
            .where((m) => m != initialMeta)
            .listen((_) => metadataEmissions++);

        // Emit 100 rapid position updates (simulating 10ms ticks)
        for (int i = 1; i <= 100; ++i) {
          testAudioHandler._positionController.add(
            Duration(milliseconds: i * 10),
          );
        }

        await Future<void>.delayed(const Duration(milliseconds: 250));

        // Throttle (100ms) guarantees drastically fewer emissions than 100 raw ticks (<= 15)
        expect(seekBarEmissions, lessThanOrEqualTo(15));
        expect(
          metadataEmissions,
          equals(0),
        ); // 0 emissions to track metadata selector

        await posSub.cancel();
        await metaSub.cancel();
        await cubit.close();
      },
    );

    test(
      '[E4] Track change mid-tick: no stale-position emission for the old track',
      () async {
        final cubit = PlayerCubit(
          audioHandler: testAudioHandler,
          repository: mockRepository,
          toggleFavoriteUseCase: mockToggleFavorite,
        );

        final song1 = SongsTableData(
          id: 201,
          title: 'Song 1',
          artist: 'Artist 1',
          album: 'Album 1',
          durationMs: 180000,
          path: '/path/201.mp3',
          isFavorite: false,
          isMissing: false,
          isDownloaded: false,
          playCount: 0,
          lastPositionMs: 0,
          source: SongSource.local,
        );
        final song2 = SongsTableData(
          id: 202,
          title: 'Song 2',
          artist: 'Artist 2',
          album: 'Album 2',
          durationMs: 240000,
          path: '/path/202.mp3',
          isFavorite: false,
          isMissing: false,
          isDownloaded: false,
          playCount: 0,
          lastPositionMs: 0,
          source: SongSource.local,
        );

        await cubit.playSong(song1, queue: [song1, song2]);
        testAudioHandler._positionController.add(const Duration(seconds: 45));
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(cubit.state.position, equals(const Duration(seconds: 45)));

        // Switch track
        await cubit.playSong(song2, queue: [song1, song2]);
        expect(cubit.state.currentSong?.id, equals(202));
        // Position is reset to zero for new track
        expect(cubit.state.position, equals(Duration.zero));

        await cubit.close();
      },
    );

    test(
      '[E4] Comprehensive audio effects & state methods coverage test',
      () async {
        final cubit = PlayerCubit(
          audioHandler: testAudioHandler,
          repository: mockRepository,
          toggleFavoriteUseCase: mockToggleFavorite,
        );

        // EQ & Presets
        await cubit.setEqualizerEnabled(true);
        expect(cubit.state.isEqEnabled, isTrue);
        await cubit.applyPreset(EqPreset.defaultPresets[1]);
        expect(
          cubit.state.eqPreset.name,
          equals(EqPreset.defaultPresets[1].name),
        );
        await cubit.setBandGain(0, 3.5);
        expect(cubit.state.eqPreset.name, equals('Custom'));
        await cubit.resetToFlat();
        expect(
          cubit.state.eqPreset.name,
          equals(EqPreset.defaultPresets.first.name),
        );
        await cubit.setBassBoost(0.6);
        await cubit.set32BandMode(true);
        await cubit.switchComparisonSlot(ComparisonSlot.slotB);
        await cubit.applyHeadphoneProfile(
          const HeadphoneProfile(
            id: 'test-1',
            name: 'AutoEQ Test',
            brand: 'Brand',
            model: 'Model',
            category: 'Custom',
            gains: [1, 2, 3],
          ),
        );
        await cubit.applyHeadphoneProfile(null);

        // Virtualizer & Dynamics
        await cubit.setVirtualizerEnabled(true);
        expect(cubit.state.isVirtualizerEnabled, isTrue);
        await cubit.setVirtualizerStrength(0.75);
        expect(cubit.state.virtualizerStrength, equals(0.75));
        await cubit.setDynamicsPreset(DynamicsPreset.studioPunch);
        expect(cubit.state.dynamicsPreset, equals(DynamicsPreset.studioPunch));
        await cubit.toggleDynamicsBypass();
        await cubit.setVolumeBoost(0.4);
        expect(cubit.state.volumeBoost, equals(0.4));
        await cubit.setSpatializerEnabled(true);
        expect(cubit.state.isSpatializerEnabled, isTrue);

        // Native DSP Stages
        await cubit.setCrossfeed(true, delayUs: 300, feedDb: -8.0);
        expect(cubit.state.isCrossfeedEnabled, isTrue);
        await cubit.setLookaheadLimiter(
          true,
          thresholdDb: -0.3,
          releaseMs: 60.0,
        );
        expect(cubit.state.isLimiterEnabled, isTrue);
        await cubit.setReverb(true, preset: 2, wetDry: 0.35);
        expect(cubit.state.isReverbEnabled, isTrue);
        await cubit.loadCustomImpulseResponse([0.1, 0.2, 0.3]);
        expect(cubit.state.reverbPreset, equals(4));
        await cubit.setStereoBalance(0.2);
        expect(cubit.state.stereoBalance, equals(0.2));
        await cubit.setMonoMix(true);
        expect(cubit.state.monoMix, isTrue);
        await cubit.setSincResampler(true);
        expect(cubit.state.isSincResamplerEnabled, isTrue);
        expect(cubit.state.isDspActive, isTrue);
        expect(cubit.state.activeDspStagesCount, greaterThan(0));

        // Master DSP enable/disable
        await cubit.setDspEffectsEnabled(false);
        expect(cubit.state.isDspActive, isFalse);
        expect(cubit.state.activeDspStagesCount, equals(0));
        await cubit.setDspEffectsEnabled(true);
        expect(cubit.state.isDspActive, isTrue);

        // Volume
        await cubit.setVolume(0.8);
        await cubit.adjustVolume(-0.1);

        // Playback controls
        await cubit.togglePlayPause();
        await cubit.seek(const Duration(seconds: 15));
        await cubit.toggleShuffle();
        await cubit.toggleRepeat();

        // Queue manipulation
        final songA = SongsTableData(
          id: 301,
          title: 'Song A',
          artist: 'Artist A',
          album: 'Album A',
          durationMs: 120000,
          path: '/path/301.mp3',
          isFavorite: false,
          isMissing: false,
          isDownloaded: false,
          playCount: 0,
          lastPositionMs: 0,
          source: SongSource.local,
        );
        final songB = SongsTableData(
          id: 302,
          title: 'Song B',
          artist: 'Artist B',
          album: 'Album B',
          durationMs: 150000,
          path: '/path/302.mp3',
          isFavorite: false,
          isMissing: false,
          isDownloaded: false,
          playCount: 0,
          lastPositionMs: 0,
          source: SongSource.local,
        );
        await cubit.playSong(songA, queue: [songA]);
        await cubit.playNext(songB);
        expect(cubit.state.queue.length, equals(2));
        await cubit.addToQueue(songA);
        expect(cubit.state.queue.length, equals(3));
        await cubit.reorderQueue(0, 2);
        await cubit.removeQueueItem(1);
        await cubit.next();
        await cubit.previous();

        // Sleep timers
        cubit.startSleepTimer(30);
        expect(
          cubit.state.sleepTimerRemaining,
          equals(const Duration(minutes: 30)),
        );
        cubit.startAbsoluteSleepTimer(
          DateTime.now().add(const Duration(hours: 1)),
        );
        cubit.startEndOfTrackTimer();
        cubit.startAfterNTracksTimer(2);
        cubit.cancelSleepTimer();
        expect(cubit.state.sleepTimerRemaining, isNull);

        // Playback speed
        await cubit.setPlaybackSpeed(1.25);
        expect(cubit.state.playbackSpeed, equals(1.25));

        // Overlays
        cubit.toggleLyricsVisibility();
        expect(cubit.state.isLyricsVisible, isTrue);
        cubit.toggleQueueVisibility();
        expect(cubit.state.isQueueVisible, isTrue);
        // Toggle favorite
        when(
          () => mockToggleFavorite(301),
        ).thenAnswer((_) async => const Right(true));
        await cubit.toggleFavorite(301);
        expect(cubit.state.currentSong?.isFavorite, isTrue);

        // Reconciled song swap
        final songC = SongsTableData(
          id: 303,
          title: 'Song C (Reconciled)',
          artist: 'Artist C',
          album: 'Album C',
          durationMs: 160000,
          path: '/path/303.mp3',
          isFavorite: false,
          isMissing: false,
          isDownloaded: true,
          playCount: 0,
          lastPositionMs: 0,
          source: SongSource.local,
        );
        when(
          () => mockRepository.getSongById(303),
        ).thenAnswer((_) async => Right(songC));
        await cubit.swapReconciledSong(301, 303);
        expect(cubit.state.currentSong?.id, equals(303));

        // Queue slot operations
        when(
          () => mockRepository.getSongsByIds([303]),
        ).thenAnswer((_) async => Right([songC]));
        await cubit.switchQueueSlot(1);
        expect(cubit.state.activeQueueSlot, equals(1));
        await cubit.switchQueueSlot(0);
        expect(cubit.state.activeQueueSlot, equals(0));

        await cubit.close();
      },
    );

    test('Queue overflow emits error message', () async {
      final cubit = PlayerCubit(
        audioHandler: testAudioHandler,
        repository: mockRepository,
        toggleFavoriteUseCase: mockToggleFavorite,
      );

      final fullQueue = List<SongsTableData>.generate(
        500,
        (i) => SongsTableData(
          id: i + 1,
          title: 'Song $i',
          artist: 'Artist',
          album: 'Album',
          durationMs: 180000,
          path: '/path/$i.mp3',
          isFavorite: false,
          isMissing: false,
          isDownloaded: false,
          playCount: 0,
          lastPositionMs: 0,
          source: SongSource.local,
        ),
      );

      await cubit.playSong(fullQueue.first, queue: fullQueue);
      expect(cubit.state.queue.length, equals(500));

      final extra = SongsTableData(
        id: 9999,
        title: 'Extra',
        artist: 'Artist',
        album: 'Album',
        durationMs: 180000,
        path: '/path/extra.mp3',
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
        source: SongSource.local,
      );

      await cubit.playNext(extra);
      expect(cubit.state.errorMessage, contains('Queue full'));

      await cubit.addToQueue(extra);
      expect(cubit.state.errorMessage, contains('Queue full'));

      await cubit.close();
    });

    test(
      'playSong centers 500-song queue window around target song beyond index 500',
      () async {
        final cubit = PlayerCubit(
          audioHandler: testAudioHandler,
          repository: mockRepository,
          toggleFavoriteUseCase: mockToggleFavorite,
        );

        final largeQueue = List<SongsTableData>.generate(
          800,
          (i) => SongsTableData(
            id: i,
            title: 'Song $i',
            artist: 'Artist',
            album: 'Album',
            durationMs: 180000,
            path: '/path/song$i.mp3',
            isFavorite: false,
            isMissing: false,
            isDownloaded: false,
            playCount: 0,
            lastPositionMs: 0,
            source: SongSource.local,
          ),
        );

        final target = largeQueue[600]; // song beyond index 500
        await cubit.playSong(target, queue: largeQueue);

        expect(cubit.state.queue.length, 500);
        expect(cubit.state.currentSong?.id, 600);
        expect(cubit.state.queue[cubit.state.currentIndex].id, 600);
        expect(cubit.state.queue.any((s) => s.id == 600), isTrue);

        await cubit.close();
      },
    );
    test('AudioService stream events update PlayerState', () async {
      final cubit = PlayerCubit(
        audioHandler: testAudioHandler,
        repository: mockRepository,
        toggleFavoriteUseCase: mockToggleFavorite,
      );

      final song = SongsTableData(
        id: 777,
        title: 'Streamed Song',
        artist: 'Streamed Artist',
        album: 'Streamed Album',
        durationMs: 200000,
        path: '/path/777.mp3',
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
        source: SongSource.local,
      );
      when(
        () => mockRepository.getSongById(777),
      ).thenAnswer((_) async => Right(song));
      when(
        () => mockRepository.getSongsByIds([777]),
      ).thenAnswer((_) async => Right([song]));

      // mediaItem
      testAudioHandler._mediaItemController.add(
        const MediaItem(
          id: '777',
          title: 'Streamed Song',
          artist: 'Streamed Artist',
          album: 'Streamed Album',
          duration: Duration(milliseconds: 200000),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(cubit.state.currentSong?.id, equals(777));

      // playbackState
      testAudioHandler._playbackStateController.add(
        PlaybackState(
          playing: true,
          processingState: AudioProcessingState.ready,
          repeatMode: AudioServiceRepeatMode.all,
          shuffleMode: AudioServiceShuffleMode.all,
          speed: 1.5,
          updatePosition: const Duration(seconds: 30),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(cubit.state.isPlaying, isTrue);
      expect(cubit.state.repeatMode, equals(PlayerRepeatMode.all));
      expect(cubit.state.isShuffle, isTrue);
      expect(cubit.state.playbackSpeed, equals(1.5));

      // errorStream
      testAudioHandler._errorController.add('Hardware decoder failure');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(cubit.state.errorMessage, equals('Hardware decoder failure'));

      // sleepTimerRemainingStream
      testAudioHandler._sleepTimerController.add(const Duration(minutes: 20));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        cubit.state.sleepTimerRemaining,
        equals(const Duration(minutes: 20)),
      );

      // audioSessionIdStream
      testAudioHandler._audioSessionIdController.add(1024);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(cubit.state.audioSessionId, equals(1024));

      // queue
      testAudioHandler._queueController.add([
        const MediaItem(
          id: '777',
          title: 'Streamed Song',
          artist: 'Streamed Artist',
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(cubit.state.queue.isNotEmpty, isTrue);

      await cubit.close();
    });
  });

  group('PlayerCubit DSP state sync', () {
    test(
      're-syncs audio effects after handler effectsReady completes',
      () async {
        testAudioHandler.readyGate = Completer<void>();
        final cubit = PlayerCubit(
          audioHandler: testAudioHandler,
          repository: mockRepository,
          toggleFavoriteUseCase: mockToggleFavorite,
        );
        addTearDown(cubit.close);

        // Pre-restore snapshot: handler defaults read as OFF.
        expect(cubit.state.isSaturationEnabled, isFalse);

        // Preference restore lands after the first sync: persisted ON state
        // becomes visible only through the effectsReady re-sync.
        testAudioHandler.persistedSaturationEnabled = true;
        testAudioHandler.readyGate!.complete();
        await pumpEventQueue();

        expect(cubit.state.isSaturationEnabled, isTrue);
        // The same re-sync must re-apply the ReplayGain-adjusted volume so a
        // restored 'on' gain mode is audible, not just displayed.
        expect(testAudioHandler.setVolumeCallCount, greaterThan(0));
      },
    );
  });
}
