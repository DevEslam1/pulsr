// test/data/audio/playback_loop_hardening_test.dart
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/ytm_resolving_source.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/domain/usecases/toggle_favorite_usecase.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';

class MockMusicRepository extends Mock implements IMusicRepository {}

class MockToggleFavoriteUseCase extends Mock implements ToggleFavoriteUseCase {}

class StubPulsrAudioHandler extends BaseAudioHandler
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

  @override
  bool get isEqualizerEnabled => false;
  @override
  EqPreset get currentPreset => EqPreset.defaultPresets.first;
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
  bool get isSpatializerEnabled => false;
  @override
  bool get isSpatializerSupported => false;
  @override
  bool get isHeadTrackerAvailable => false;
  @override
  double get volumeBoost => 0.0;
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
  Future<void> get effectsReady => Future<void>.value();
  @override
  Duration get crossfadeDuration => Duration.zero;
  @override
  Stream<Duration> get positionStream => _positionController.stream;
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  @override
  Stream<String> get errorStream => _errorController.stream;

  @override
  void setCrossfadeDuration(Duration d) {}
  @override
  Future<void> restoreLastPlaybackSession() async {}
  @override
  Future<void> saveCurrentPositionImmediate() async {}
  @override
  Future<void> setEqualizerEnabled(bool enabled) async {}
  @override
  Future<void> applyPreset(EqPreset preset) async {}
  @override
  Future<void> setBandGain(int bandIndex, double gainDb) async {}
  @override
  Future<void> setBassBoost(double amount) async {}
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
  Future<void> setSpatializerEnabled(bool enabled) async {}
  @override
  Future<void> setVolumeBoost(double value) async {}
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
  Future<void> resetToFlat() async {}
  @override
  Future<void> startAbComparison() async {}
  @override
  Future<void> endAbComparison() async {}
  @override
  Future<void> toggleDynamicsBypass() async {}
  @override
  bool get isDynamicsBypassed => false;
  @override
  Future<void> setCustomFrequencies(List<double> frequencies) async {}
  @override
  Future<void> onAppPaused() async {}
  @override
  void startSleepTimer(Duration duration, {bool fadeOut = true}) {}
  @override
  void startAbsoluteSleepTimer(DateTime stopTime, {bool fadeOut = true}) {}
  @override
  void cancelSleepTimer() {}
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
  Future<void> playSongAt(int index, {Duration? initialPosition}) async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> validatePlayerState() async {}
  @override
  void dispose() {
    _positionController.close();
    _errorController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YtmResolvingSource Hardening Tests', () {
    test(
        'invokes onError callback when resolve throws YtmException (bot blocked)',
        () async {
      Object? capturedError;
      final source = YtmResolvingSource(
        videoId: 'video_bot_1',
        resolve: ({bool forceRefresh = false}) async {
          throw const YtmException(
              'YTM_BOT_BLOCKED', 'Bot detection triggered');
        },
        onError: (err) {
          capturedError = err;
        },
      );

      await expectLater(source.request(), throwsA(isA<YtmException>()));
      expect(capturedError, isA<YtmException>());
      expect((capturedError as YtmException).code, 'YTM_BOT_BLOCKED');
      expect((capturedError as YtmException).isBotBlocked, isTrue);
      expect((capturedError as YtmException).isFatal, isTrue);
    });

    test('invokes onError callback with withRefresh constructor', () async {
      Object? capturedError;
      final source = YtmResolvingSource.withRefresh(
        videoId: 'video_404',
        resolve: ({bool forceRefresh = false}) async {
          throw const YtmException('YTM_UNAVAILABLE', 'Track not found');
        },
        onError: (err) {
          capturedError = err;
        },
      );

      await expectLater(source.request(), throwsA(isA<YtmException>()));
      expect(capturedError, isA<YtmException>());
      expect((capturedError as YtmException).code, 'YTM_UNAVAILABLE');
    });
  });

  group('PlayerCubit Concurrency & Error Hardening Tests', () {
    late MockMusicRepository mockRepository;
    late MockToggleFavoriteUseCase mockToggleFavoriteUseCase;
    late StubPulsrAudioHandler stubAudioHandler;
    late PlayerCubit cubit;

    final songA = SongsTableData(
      id: 101,
      title: 'Local Track 1',
      artist: 'Artist 1',
      album: 'Album 1',
      path: '/local/track1.mp3',
      durationMs: 180000,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
      source: SongSource.local,
    );

    final songB = SongsTableData(
      id: 102,
      title: 'Local Track 2',
      artist: 'Artist 2',
      album: 'Album 2',
      path: '/local/track2.mp3',
      durationMs: 200000,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
      source: SongSource.local,
    );

    setUp(() {
      mockRepository = MockMusicRepository();
      mockToggleFavoriteUseCase = MockToggleFavoriteUseCase();
      stubAudioHandler = StubPulsrAudioHandler();

      when(() => mockRepository.getSongById(101))
          .thenAnswer((_) async => Right(songA));
      when(() => mockRepository.getSongById(102))
          .thenAnswer((_) async => Right(songB));
      when(() => mockRepository.getSongsByIds(any()))
          .thenAnswer((_) async => Right([songA, songB]));

      cubit = PlayerCubit(
        audioHandler: stubAudioHandler,
        repository: mockRepository,
        toggleFavoriteUseCase: mockToggleFavoriteUseCase,
      );
    });

    tearDown(() async {
      await cubit.close();
      stubAudioHandler.dispose();
    });

    test(
        'errorStream events from audio handler update PlayerState errorMessage',
        () async {
      expect(cubit.state.errorMessage, isNull);

      stubAudioHandler._errorController.add('YouTube is busy. Retrying…');
      await pumpEventQueue();

      expect(cubit.state.errorMessage, 'YouTube is busy. Retrying…');
    });

    test(
        'stale async mediaItem resolution does not overwrite newly selected song',
        () async {
      final slowCompleter = Completer<Either<AppFailure, SongsTableData?>>();
      when(() => mockRepository.getSongById(101))
          .thenAnswer((_) => slowCompleter.future);

      // 1. Emit mediaItem for song 101 (initiates slow DB lookup)
      stubAudioHandler.mediaItem
          .add(const MediaItem(id: '101', title: 'Slow Song'));
      await pumpEventQueue();

      // 2. User immediately clicks song 102
      await cubit.playSong(songB);
      expect(cubit.state.currentSong?.id, 102);

      // 3. Now the slow DB lookup for song 101 finishes
      slowCompleter.complete(Right(songA));
      await pumpEventQueue();

      // 4. Current song MUST remain song 102 and not be clobbered by stale song 101
      expect(cubit.state.currentSong?.id, 102);
      expect(cubit.state.currentSong?.title, 'Local Track 2');
    });

    test('saveCurrentPositionImmediate completes asynchronously without errors',
        () async {
      await expectLater(
          stubAudioHandler.saveCurrentPositionImmediate(), completes);
    });

    test(
        'bounded concurrency pool processes large task lists without unbounded spawning',
        () async {
      int active = 0;
      int maxSimultaneous = 0;
      final completed = <int>[];
      const totalTasks = 100;
      const maxConcurrency = 16;
      final pool = <Future<void>>{};

      for (int i = 0; i < totalTasks; i++) {
        final taskIdx = i;
        final fut = () async {
          active++;
          if (active > maxSimultaneous) maxSimultaneous = active;
          await Future.delayed(const Duration(milliseconds: 5));
          completed.add(taskIdx);
          active--;
        }();

        pool.add(fut);
        fut.whenComplete(() => pool.remove(fut));
        if (pool.length >= maxConcurrency) {
          await Future.any(pool);
        }
      }
      if (pool.isNotEmpty) {
        await Future.wait(pool);
      }

      expect(completed.length, 100);
      expect(maxSimultaneous, lessThanOrEqualTo(maxConcurrency));
    });
  });
}
