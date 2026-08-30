// test/widget_test.dart
import 'package:audio_service/audio_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/theme/dynamic_theme_cubit.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';
import 'package:pulsr/data/repositories/smart_playlist_engine.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/domain/usecases/get_albums_usecase.dart';
import 'package:pulsr/domain/usecases/get_artists_usecase.dart';
import 'package:pulsr/domain/usecases/get_genres_usecase.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';
import 'package:pulsr/domain/usecases/get_years_usecase.dart';
import 'package:pulsr/domain/usecases/get_favorites_usecase.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/domain/usecases/search_music_usecase.dart';
import 'package:pulsr/domain/usecases/toggle_favorite_usecase.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/repositories/download_repository_interface.dart';
import 'package:pulsr/domain/usecases/queue_download.dart';
import 'package:pulsr/domain/usecases/pause_download.dart';
import 'package:pulsr/domain/usecases/resume_download.dart';
import 'package:pulsr/domain/usecases/retry_download.dart';
import 'package:pulsr/domain/usecases/delete_download.dart';
import 'package:pulsr/domain/usecases/observe_downloads.dart';
import 'package:pulsr/domain/usecases/get_download_storage_stats.dart';
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/playlists/cubit/playlist_cubit.dart';
import 'package:pulsr/features/search/cubit/search_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/widgets/widget_service.dart';
import 'package:pulsr/main.dart';
import 'package:mocktail/mocktail.dart';

import 'package:shared_preferences/shared_preferences.dart';

class MockDownloadRepo extends Mock implements IDownloadRepository {}

class MockPulsrAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler
    implements PulsrAudioHandler {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  MockPulsrAudioHandler() {
    playbackState.add(PlaybackState(
      controls: [],
      systemActions: const {},
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
    queue.add([]);
  }

  @override
  double get volume => 1.0;
  @override
  SongsTableData? get currentSong => null;
  @override
  int? get currentAudioSessionId => null;
  @override
  Stream<int?> get audioSessionIdStream => Stream<int?>.empty();
  @override
  Future<void> setVolume(double volume) async {}
  @override
  bool get isEqualizerEnabled => false;
  @override
  EqPreset get currentPreset => EqPreset.defaultPresets.first;
  @override
  Duration get crossfadeDuration => Duration.zero;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
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
  Future<void> get effectsReady => Future<void>.value();

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
  Stream<String> get errorStream => const Stream.empty();
  @override
  void dispose() {}
  @override
  Future<void> playSongAt(int index, {Duration? initialPosition}) async {}
  @override
  Future<void> validatePlayerState() async {}
}

void main() {
  setUp(() async {
    await getIt.reset();
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.pulsr.music/hires_dac'),
            (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.pulsr.music/hires_dac_events'),
            (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.pulsr.music/proxy'), (call) async => null);

    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = MusicRepository(db);
    final smartEngine = SmartPlaylistEngine(db);
    final audioHandler = MockPulsrAudioHandler();
    final scannerService = MediaScannerService(repo);

    final getSongsUseCase = GetSongsUseCase(repo);
    final getAlbumsUseCase = GetAlbumsUseCase(repo);
    final getArtistsUseCase = GetArtistsUseCase(repo);
    final getGenresUseCase = GetGenresUseCase(repo);
    final getYearsUseCase = GetYearsUseCase(repo);
    final getFavoritesUseCase = GetFavoritesUseCase(repo);
    final toggleFavoriteUseCase = ToggleFavoriteUseCase(repo);
    final searchMusicUseCase = SearchMusicUseCase(repo);
    final playlistUseCases = PlaylistUseCases(repo, smartEngine);
    final folderUseCases = FolderUseCases(repo);
    final widgetService = WidgetService();

    getIt.registerSingleton<AppDatabase>(db);
    getIt.registerSingleton<IMusicRepository>(repo);
    getIt.registerSingleton<MusicRepository>(repo);
    getIt.registerSingleton<PulsrAudioHandler>(audioHandler);
    getIt.registerSingleton<MediaScannerService>(scannerService);
    getIt.registerSingleton<GetSongsUseCase>(getSongsUseCase);
    getIt.registerSingleton<GetAlbumsUseCase>(getAlbumsUseCase);
    getIt.registerSingleton<GetArtistsUseCase>(getArtistsUseCase);
    getIt.registerSingleton<GetGenresUseCase>(getGenresUseCase);
    getIt.registerSingleton<GetYearsUseCase>(getYearsUseCase);
    getIt.registerSingleton<GetFavoritesUseCase>(getFavoritesUseCase);
    getIt.registerSingleton<ToggleFavoriteUseCase>(toggleFavoriteUseCase);
    getIt.registerSingleton<SearchMusicUseCase>(searchMusicUseCase);
    getIt.registerSingleton<PlaylistUseCases>(playlistUseCases);
    getIt.registerSingleton<FolderUseCases>(folderUseCases);
    getIt.registerSingleton<WidgetService>(widgetService);

    getIt.registerSingleton<DynamicThemeCubit>(DynamicThemeCubit());
    getIt.registerFactory<PlayerCubit>(() => PlayerCubit(
          audioHandler: audioHandler,
          repository: repo,
          toggleFavoriteUseCase: toggleFavoriteUseCase,
        ));
    getIt.registerFactory<LibraryCubit>(() => LibraryCubit(
          getSongsUseCase: getSongsUseCase,
          getAlbumsUseCase: getAlbumsUseCase,
          getArtistsUseCase: getArtistsUseCase,
          getGenresUseCase: getGenresUseCase,
          getYearsUseCase: getYearsUseCase,
          getFavoritesUseCase: getFavoritesUseCase,
          toggleFavoriteUseCase: toggleFavoriteUseCase,
          folderUseCases: folderUseCases,
        ));
    getIt.registerFactory<SearchCubit>(() => SearchCubit(
        searchUseCase: searchMusicUseCase, folderUseCases: folderUseCases));
    final mockDownloadRepo = MockDownloadRepo();
    when(() => mockDownloadRepo.observeDownloads())
        .thenAnswer((_) => const Stream.empty());
    when(() => mockDownloadRepo.getAllDownloads())
        .thenAnswer((_) async => []);
    when(() => mockDownloadRepo.getStorageStats())
        .thenAnswer((_) async => const Right(StorageStats()));

    final queueDownloadUseCase = QueueDownloadUseCase(mockDownloadRepo);
    final pauseDownloadUseCase = PauseDownloadUseCase(mockDownloadRepo);
    final resumeDownloadUseCase = ResumeDownloadUseCase(mockDownloadRepo);
    final retryDownloadUseCase = RetryDownloadUseCase(mockDownloadRepo);
    final deleteDownloadUseCase = DeleteDownloadUseCase(mockDownloadRepo);
    final observeDownloadsUseCase = ObserveDownloadsUseCase(mockDownloadRepo);
    final getDownloadStorageStatsUseCase = GetDownloadStorageStatsUseCase(mockDownloadRepo);

    getIt.registerSingleton<IDownloadRepository>(mockDownloadRepo);
    getIt.registerSingleton<QueueDownloadUseCase>(queueDownloadUseCase);
    getIt.registerSingleton<PauseDownloadUseCase>(pauseDownloadUseCase);
    getIt.registerSingleton<ResumeDownloadUseCase>(resumeDownloadUseCase);
    getIt.registerSingleton<RetryDownloadUseCase>(retryDownloadUseCase);
    getIt.registerSingleton<DeleteDownloadUseCase>(deleteDownloadUseCase);
    getIt.registerSingleton<ObserveDownloadsUseCase>(observeDownloadsUseCase);
    getIt.registerSingleton<GetDownloadStorageStatsUseCase>(getDownloadStorageStatsUseCase);
    getIt.registerSingleton<DownloadsCubit>(DownloadsCubit(
      queueDownloadUseCase,
      pauseDownloadUseCase,
      resumeDownloadUseCase,
      retryDownloadUseCase,
      deleteDownloadUseCase,
      observeDownloadsUseCase,
      getDownloadStorageStatsUseCase,
    ));

    getIt.registerFactory<PlaylistCubit>(
        () => PlaylistCubit(playlistUseCases: playlistUseCases));
    getIt.registerSingleton<SettingsCubit>(
        SettingsCubit(scannerService: scannerService));

    await tester.runAsync(() async {
      await tester.pumpWidget(const PulsrApp());
      await tester.pump();
      expect(find.byType(PulsrApp), findsOneWidget);
      // Splash shows first
      expect(find.text('Pulsr Music'), findsOneWidget);
      await Future.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await audioHandler.stop();
      await db.close();
    });
  });
}
