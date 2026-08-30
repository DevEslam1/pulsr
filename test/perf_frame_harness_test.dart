// test/perf_frame_harness_test.dart
//
// Performance frame-timing harness (pulsr perf task, Phase 0 + Phase 2).
//
// Measures per-frame widget build/layout/paint costs on the CURRENT code using
// the AutomatedTestWidgetsFlutterBinding (tester.pump executes build+layout+
// paint synchronously, so a Stopwatch around it captures the full frame cost).
// Writes JSON to build/perf_metrics/latest.json with the documented schema and
// prints a human-readable table.
//
// IMPORTANT: timings are host-side widget-test measurements (build-scope
// evidence), NOT device frame rates. Only sanity assertions (>0) are used so
// the suite stays green on any machine.
//
// Wiring is copied from test/widget_test.dart (in-memory drift DB,
// MockPulsrAudioHandler, SharedPreferences mocks, get_it registrations) and
// seeded with 1200 songs / 1200 playlist entries.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:mocktail/mocktail.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/theme/dynamic_theme_cubit.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';
import 'package:pulsr/data/repositories/smart_playlist_engine.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';
import 'package:pulsr/domain/models/genre_item.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/repositories/download_repository_interface.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/domain/usecases/get_albums_usecase.dart';
import 'package:pulsr/domain/usecases/get_artists_usecase.dart';
import 'package:pulsr/domain/usecases/get_genres_usecase.dart';
import 'package:pulsr/domain/usecases/get_years_usecase.dart';
import 'package:pulsr/domain/usecases/get_favorites_usecase.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/domain/usecases/search_music_usecase.dart';
import 'package:pulsr/domain/usecases/toggle_favorite_usecase.dart';
import 'package:pulsr/domain/usecases/queue_download.dart';
import 'package:pulsr/domain/usecases/pause_download.dart';
import 'package:pulsr/domain/usecases/resume_download.dart';
import 'package:pulsr/domain/usecases/retry_download.dart';
import 'package:pulsr/domain/usecases/delete_download.dart';
import 'package:pulsr/domain/usecases/observe_downloads.dart';
import 'package:pulsr/domain/usecases/get_download_storage_stats.dart';
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';
import 'package:pulsr/features/genre_detail/presentation/genre_detail_screen.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/presentation/library_screen.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/now_playing_screen.dart';
import 'package:pulsr/features/playlist_detail/presentation/playlist_detail_screen.dart';
import 'package:pulsr/features/playlists/cubit/playlist_cubit.dart';
import 'package:pulsr/features/search/cubit/search_cubit.dart';
import 'package:pulsr/features/search/presentation/search_screen.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/widgets/widget_service.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockDownloadRepo extends Mock implements IDownloadRepository {}

/// Stub repository used to drive [GenreDetailScreen]'s song stream directly
/// (no drift write machinery involved).
class _FakeMusicRepo extends Mock implements IMusicRepository {}

class MockPulsrAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler
    implements PulsrAudioHandler {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  MockPulsrAudioHandler() {
    playbackState.add(
      PlaybackState(
        controls: [],
        systemActions: const {},
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
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
  Future<void> loadQueue(
    List<SongsTableData> songs, {
    int initialIndex = 0,
    Duration? initialPosition,
  }) async {}
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

/// Inert rebuild trigger for idle-floor frames. `nudge()` schedules one
/// frame whose build phase has no meaningful work: [build] returns the SAME
/// const child instance, so the descendant element is skipped entirely
/// (identical widget) — the flushed frame is the idle frame floor (frame
/// pipeline + no-op layout/paint). Needed because `tester.pump()`
/// short-circuits when no frame is scheduled
/// (AutomatedTestWidgetsFlutterBinding.pump only runs a frame if
/// `hasScheduledFrame`).
class _Nudge extends StatefulWidget {
  const _Nudge({super.key, required this.child});
  final Widget child;

  @override
  State<_Nudge> createState() => _NudgeState();
}

class _NudgeState extends State<_Nudge> {
  void nudge() => setState(() {});

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Accumulates per-frame microsecond samples for one metric.
class _PerfMetric {
  final String id;
  final List<double> samplesUs = [];
  String? error;

  _PerfMetric(this.id);

  void add(double us) => samplesUs.add(us);

  double get avgUs =>
      samplesUs.isEmpty
          ? 0
          : samplesUs.reduce((a, b) => a + b) / samplesUs.length;

  double get p95Us {
    if (samplesUs.isEmpty) return 0;
    final s = [...samplesUs]..sort();
    final idx = ((s.length * 0.95).ceil() - 1).clamp(0, s.length - 1);
    return s[idx];
  }
}

void main() {
  setUp(() async {
    await getIt.reset();
  });

  testWidgets('perf frame harness', (WidgetTester tester) async {
    // Large portrait surface (logical 800x1300) so no borderline layout
    // artifacts (e.g. two-pane landscape) pollute the timed frames.
    tester.view.physicalSize = const Size(1600, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    // Silence platform channels that are not exercised by widget tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.pulsr.music/hires_dac'),
          (call) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.pulsr.music/hires_dac_events'),
          (call) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.pulsr.music/proxy'),
          (call) async => null,
        );

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
    getIt.registerFactory<PlayerCubit>(
      () => PlayerCubit(
        audioHandler: audioHandler,
        repository: repo,
        toggleFavoriteUseCase: toggleFavoriteUseCase,
      ),
    );
    getIt.registerFactory<LibraryCubit>(
      () => LibraryCubit(
        getSongsUseCase: getSongsUseCase,
        getAlbumsUseCase: getAlbumsUseCase,
        getArtistsUseCase: getArtistsUseCase,
        getGenresUseCase: getGenresUseCase,
        getYearsUseCase: getYearsUseCase,
        getFavoritesUseCase: getFavoritesUseCase,
        toggleFavoriteUseCase: toggleFavoriteUseCase,
        folderUseCases: folderUseCases,
      ),
    );
    getIt.registerFactory<SearchCubit>(
      () => SearchCubit(
        searchUseCase: searchMusicUseCase,
        folderUseCases: folderUseCases,
      ),
    );
    final mockDownloadRepo = MockDownloadRepo();
    when(
      () => mockDownloadRepo.observeDownloads(),
    ).thenAnswer((_) => const Stream.empty());
    when(() => mockDownloadRepo.getAllDownloads()).thenAnswer((_) async => []);
    when(
      () => mockDownloadRepo.getStorageStats(),
    ).thenAnswer((_) async => const Right(StorageStats()));

    final queueDownloadUseCase = QueueDownloadUseCase(mockDownloadRepo);
    final pauseDownloadUseCase = PauseDownloadUseCase(mockDownloadRepo);
    final resumeDownloadUseCase = ResumeDownloadUseCase(mockDownloadRepo);
    final retryDownloadUseCase = RetryDownloadUseCase(mockDownloadRepo);
    final deleteDownloadUseCase = DeleteDownloadUseCase(mockDownloadRepo);
    final observeDownloadsUseCase = ObserveDownloadsUseCase(mockDownloadRepo);
    final getDownloadStorageStatsUseCase = GetDownloadStorageStatsUseCase(
      mockDownloadRepo,
    );

    getIt.registerSingleton<IDownloadRepository>(mockDownloadRepo);
    getIt.registerSingleton<QueueDownloadUseCase>(queueDownloadUseCase);
    getIt.registerSingleton<PauseDownloadUseCase>(pauseDownloadUseCase);
    getIt.registerSingleton<ResumeDownloadUseCase>(resumeDownloadUseCase);
    getIt.registerSingleton<RetryDownloadUseCase>(retryDownloadUseCase);
    getIt.registerSingleton<DeleteDownloadUseCase>(deleteDownloadUseCase);
    getIt.registerSingleton<ObserveDownloadsUseCase>(observeDownloadsUseCase);
    getIt.registerSingleton<GetDownloadStorageStatsUseCase>(
      getDownloadStorageStatsUseCase,
    );
    getIt.registerSingleton<DownloadsCubit>(
      DownloadsCubit(
        queueDownloadUseCase,
        pauseDownloadUseCase,
        resumeDownloadUseCase,
        retryDownloadUseCase,
        deleteDownloadUseCase,
        observeDownloadsUseCase,
        getDownloadStorageStatsUseCase,
      ),
    );

    getIt.registerFactory<PlaylistCubit>(
      () => PlaylistCubit(playlistUseCases: playlistUseCases),
    );
    final settingsCubit = SettingsCubit(scannerService: scannerService);
    getIt.registerSingleton<SettingsCubit>(settingsCubit);

    // Deterministic non-artwork theming so the NowPlaying listener does not try
    // to extract palettes from artwork files during the timed loops.
    settingsCubit.emit(
      settingsCubit.state.copyWith(
        themeColorSource: ThemeColorSource.custom,
        customAccentColorValue: 0xFF7C4DFF,
      ),
    );

    // ----------------------------------------------------------------------
    // Seed a generous library (>= 1000 songs) + a playlist with 1200 entries.
    // ----------------------------------------------------------------------
    await tester.runAsync(() async {
      final rows = <SongsTableCompanion>[];
      for (int i = 0; i < 1200; i++) {
        rows.add(
          SongsTableCompanion.insert(
            id: Value(i + 1),
            title: 'Perf Song ${i.toString().padLeft(5, '0')}',
            path: '/storage/emulated/0/Music/perf/song_$i.flac',
            artist: Value('Perf Artist ${i % 100}'),
            artistId: Value(i % 100 + 1),
            album: Value('Perf Album ${i % 50}'),
            albumId: Value(i % 50 + 1),
            durationMs: Value(180000 + i),
            genre: Value('PerfTest'),
            year: Value(2000 + (i % 24)),
            dateAdded: Value(1600000000 + i),
            playCount: Value(i % 7),
            isFavorite: Value(i % 5 == 0),
            sampleRate: Value(44100),
            bitDepth: Value(16),
          ),
        );
      }
      await db.batch((b) => b.insertAll(db.songsTable, rows));

      final playlistId = await db
          .into(db.playlistsTable)
          .insert(PlaylistsTableCompanion.insert(name: 'Perf Playlist'));
      final entries = <PlaylistEntriesTableCompanion>[];
      for (int i = 0; i < 1200; i++) {
        entries.add(
          PlaylistEntriesTableCompanion.insert(
            playlistId: playlistId,
            songId: i + 1,
            orderIndex: i,
          ),
        );
      }
      await db.batch((b) => b.insertAll(db.playlistEntriesTable, entries));
    });

    final metrics = <String, _PerfMetric>{};
    _PerfMetric metric(String id) =>
        metrics.putIfAbsent(id, () => _PerfMetric(id));

    Future<double> timePump() async {
      final sw = Stopwatch()..start();
      await tester.pump();
      sw.stop();
      return sw.elapsedMicroseconds.toDouble();
    }

    // Times a pump after scheduling an inert rebuild on `_Nudge`. The frame
    // does no downstream build work (const child), so this measures the
    // idle frame floor even though pump() would otherwise short-circuit.
    Future<double> timeIdlePump(GlobalKey<_NudgeState> nudgeKey) async {
      nudgeKey.currentState!.nudge();
      final sw = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 1));
      sw.stop();
      return sw.elapsedMicroseconds.toDouble();
    }

    // Records `samples` idle-pump frames for `metricId`, empirically deciding
    // between a plain pump() (only meaningful when something — e.g. a running
    // animation — keeps scheduling frames) and nudged pump(1ms) frames (used
    // when pump() short-circuits on an empty frame schedule). Prints what it
    // observes.
    Future<void> measureIdleFloor({
      required String metricId,
      required GlobalKey<_NudgeState> nudgeKey,
      required int samples,
    }) async {
      final plainProbe = <double>[];
      final nudgedProbe = <double>[];
      for (int i = 0; i < 3; i++) {
        final sw = Stopwatch()..start();
        await tester.pump();
        sw.stop();
        plainProbe.add(sw.elapsedMicroseconds.toDouble());
        nudgedProbe.add(await timeIdlePump(nudgeKey));
      }
      double avg(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
      final plainAvg = avg(plainProbe);
      final nudgedAvg = avg(nudgedProbe);
      // If a plain pump costs the same order as a nudged frame, real frames
      // are being flushed (frames continuously scheduled); otherwise pump()
      // short-circuited because nothing was dirty or scheduled.
      final plainFlushesRealFrames = plainAvg > nudgedAvg * 0.5;
      // ignore: avoid_print
      print(
        'HARNESS $metricId probe: plain_pump_avg='
        '${plainAvg.toStringAsFixed(1)}us, nudged_frame_avg='
        '${nudgedAvg.toStringAsFixed(1)}us -> '
        '${plainFlushesRealFrames ? 'recording plain pumps (frames continuously scheduled)' : 'pump() short-circuits; recording nudged pump(1ms) frames'}',
      );
      for (int i = 0; i < samples; i++) {
        if (plainFlushesRealFrames) {
          metric(metricId).add(await timePump());
        } else {
          metric(metricId).add(await timeIdlePump(nudgeKey));
        }
      }
    }

    Widget host(Widget child, {required PlayerCubit player}) {
      return MultiBlocProvider(
        providers: [
          BlocProvider<PlayerCubit>.value(value: player),
          BlocProvider<SettingsCubit>.value(value: settingsCubit),
          BlocProvider<DynamicThemeCubit>.value(
            value: getIt<DynamicThemeCubit>(),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AuraTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      );
    }

    final songs = await tester.runAsync(() => getSongsUseCase.getAllSongs());
    final allSongs =
        songs?.fold((l) => <SongsTableData>[], (r) => r) ?? <SongsTableData>[];
    expect(allSongs.length, greaterThanOrEqualTo(1000));

    // ======================================================================
    // 1+2. Now Playing position tick rebuild cost (F-01 / F-02)
    // ======================================================================
    final playerCubit = getIt<PlayerCubit>();
    playerCubit.emit(
      PlayerState(
        currentSong: allSongs.first,
        isPlaying: true,
        position: Duration.zero,
        duration: const Duration(minutes: 3, seconds: 12),
        queue: allSongs,
      ),
    );

    try {
      await tester.pumpWidget(
        host(const NowPlayingScreen(), player: playerCubit),
      );
      await tester.pump();
      // Warm-up frames (settle initial theme/animation timers).
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      var pos = playerCubit.state.position;
      for (int i = 0; i < 20; i++) {
        pos += const Duration(milliseconds: 200);
        playerCubit.emit(playerCubit.state.copyWith(position: pos));
        metric('now_playing_position_tick_us').add(await timePump());
      }
    } catch (e, st) {
      metric('now_playing_position_tick_us').error = '${e.runtimeType}: $e';
      // ignore: avoid_print
      print('HARNESS now_playing error: $e\n$st');
    }

    // Classic theme tick loop (fresh screen, same playing state).
    try {
      await tester.pumpWidget(
        host(const NowPlayingScreen(), player: playerCubit),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      var pos = playerCubit.state.position;
      for (int i = 0; i < 20; i++) {
        pos += const Duration(milliseconds: 200);
        playerCubit.emit(playerCubit.state.copyWith(position: pos));
        metric('theme_classic_position_tick_us').add(await timePump());
      }
    } catch (e, st) {
      metric('theme_classic_position_tick_us').error = '${e.runtimeType}: $e';
      // ignore: avoid_print
      print('HARNESS classic theme error: $e\n$st');
    }

    // ======================================================================
    // 2b. Idle pump floor on the settled NowPlayingScreen (same screen and
    // state as 1., with an inert _Nudge wrapper so a frame can be flushed
    // without dirtying anything).
    // ======================================================================
    {
      final nudgeKey = GlobalKey<_NudgeState>();
      try {
        await tester.pumpWidget(
          host(
            _Nudge(key: nudgeKey, child: const NowPlayingScreen()),
            player: playerCubit,
          ),
        );
        await tester.pump();
        // Warm-up frames (settle initial theme/animation timers).
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));

        await measureIdleFloor(
          metricId: 'idle_pump_floor_us',
          nudgeKey: nudgeKey,
          samples: 15,
        );

        // Empirical check: the idle floor must sit meaningfully below the
        // whole-screen rebuild cost (position tick loop from 1.).
        // ignore: avoid_print
        print(
          'HARNESS idle floor check: idle_pump_floor_avg='
          '${metric('idle_pump_floor_us').avgUs.toStringAsFixed(1)}us vs '
          'now_playing_position_tick_avg='
          '${metric('now_playing_position_tick_us').avgUs.toStringAsFixed(1)}us',
        );
      } catch (e, st) {
        metric('idle_pump_floor_us').error = '${e.runtimeType}: $e';
        // ignore: avoid_print
        print('HARNESS idle floor error: $e\n$st');
      }
    }

    // ======================================================================
    // 3+4. Genre detail first build + scroll frame cost (F-04)
    // ======================================================================
    try {
      await tester.pumpWidget(
        host(
          GenreDetailScreen(
            genreItem: const GenreItem(name: 'PerfTest', songCount: 1200),
          ),
          player: playerCubit,
        ),
      );
      await tester.pump();
      // Let the drift watch stream emit its first data batch.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(milliseconds: 16));

      // First frame that renders the genre screen: the track list is a
      // virtualized SliverList.builder now, so only the visible tiles are
      // built on this frame.
      metric('genre_detail_first_build_us').add(await timePump());

      // 25 scroll frames.
      final scrollable = find.byType(Scrollable).first;
      for (int i = 0; i < 25; i++) {
        await tester.drag(scrollable, const Offset(0, -400));
        metric('genre_detail_scroll_frame_us').add(await timePump());
      }
    } catch (e, st) {
      metric('genre_detail_first_build_us').error = '${e.runtimeType}: $e';
      metric('genre_detail_scroll_frame_us').error = '${e.runtimeType}: $e';
      // ignore: avoid_print
      print('HARNESS genre detail error: $e\n$st');
    }

    // ======================================================================
    // 3b. Genre detail rebuild on one library re-emit (F-04)
    // ======================================================================
    // The screen receives its songs via StreamBuilder on
    // GetGenresUseCase.watchGenreSongs. The re-emit is simulated the way
    // the library layer delivers state: the screen's use case is stubbed
    // with a StreamController we drive, and each sample adds a NEW
    // List<SongsTableData> instance with identical content. The timed pump
    // then captures the state-change rebuild frame: the virtualized
    // SliverList.builder rebuilds only the visible tiles (the former
    // non-virtualized list rebuilt every item's widget subtree).
    {
      try {
        final genreSongsController =
            StreamController<Result<List<SongsTableData>>>();
        final fakeRepo = _FakeMusicRepo();
        when(
          () => fakeRepo.watchGenreSongs('PerfTest'),
        ).thenAnswer((_) => genreSongsController.stream);
        final genreUseCase = GetGenresUseCase(fakeRepo);

        await tester.pumpWidget(
          host(
            GenreDetailScreen(
              genreItem: const GenreItem(name: 'PerfTest', songCount: 1200),
              getGenresUseCase: genreUseCase,
            ),
            player: playerCubit,
          ),
        );
        await tester.pump();
        // Initial delivery: the genre's songs (same content the drift watch
        // would emit) so the track list is on screen.
        genreSongsController.add(
          Right<AppFailure, List<SongsTableData>>(List.of(allSongs)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        // Sanity (non-timing): the track list must be rendered.
        expect(
          find.byType(SliverList),
          findsOneWidget,
          reason: 'genre screen did not render the emitted song list',
        );

        for (int i = 0; i < 10; i++) {
          // One library re-emit: NEW list instance, identical content.
          genreSongsController.add(
            Right<AppFailure, List<SongsTableData>>(List.of(allSongs)),
          );
          metric('genre_rebuild_on_emit_us').add(await timePump());
        }
        unawaited(genreSongsController.close());
      } catch (e, st) {
        metric('genre_rebuild_on_emit_us').error = '${e.runtimeType}: $e';
        // ignore: avoid_print
        print('HARNESS genre re-emit error: $e\n$st');
      }
    }

    // ======================================================================
    // 5. Playlist detail scroll frame cost (F-04)
    // ======================================================================
    try {
      final playlist = await tester.runAsync(() async {
        final rows =
            await (db.select(db.playlistsTable)
              ..where((t) => t.name.equals('Perf Playlist'))).get();
        return rows.first;
      });
      await tester.pumpWidget(
        host(PlaylistDetailScreen(playlist: playlist!), player: playerCubit),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(milliseconds: 16));

      final scrollable = find.byType(Scrollable).first;
      for (int i = 0; i < 25; i++) {
        await tester.drag(scrollable, const Offset(0, -400));
        metric('playlist_detail_scroll_frame_us').add(await timePump());
      }
    } catch (e, st) {
      metric('playlist_detail_scroll_frame_us').error = '${e.runtimeType}: $e';
      // ignore: avoid_print
      print('HARNESS playlist detail error: $e\n$st');
    }

    // ======================================================================
    // 6. Search keystroke frame cost (F-03)
    // ======================================================================
    final searchCubit = getIt<SearchCubit>();
    try {
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<PlayerCubit>.value(value: playerCubit),
            BlocProvider<SettingsCubit>.value(value: settingsCubit),
            BlocProvider<DynamicThemeCubit>.value(
              value: getIt<DynamicThemeCubit>(),
            ),
            BlocProvider<SearchCubit>.value(value: searchCubit),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AuraTheme.darkTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SearchScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final field = find.byType(TextField);
      for (int i = 0; i < 10; i++) {
        await tester.enterText(field, 'needle ${i * 37}');
        metric('search_keystroke_frame_us').add(await timePump());
      }
      await tester.pump(const Duration(seconds: 1)); // flush debounce timer
    } catch (e, st) {
      metric('search_keystroke_frame_us').error = '${e.runtimeType}: $e';
      // ignore: avoid_print
      print('HARNESS search error: $e\n$st');
    }

    // ======================================================================
    // 6b. Search screen idle pump floor (5 samples, same procedure as 2b).
    // ======================================================================
    {
      final searchNudgeKey = GlobalKey<_NudgeState>();
      try {
        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<PlayerCubit>.value(value: playerCubit),
              BlocProvider<SettingsCubit>.value(value: settingsCubit),
              BlocProvider<DynamicThemeCubit>.value(
                value: getIt<DynamicThemeCubit>(),
              ),
              BlocProvider<SearchCubit>.value(value: searchCubit),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AuraTheme.darkTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: _Nudge(key: searchNudgeKey, child: const SearchScreen()),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        await measureIdleFloor(
          metricId: 'search_idle_pump_floor_us',
          nudgeKey: searchNudgeKey,
          samples: 5,
        );
      } catch (e, st) {
        metric('search_idle_pump_floor_us').error = '${e.runtimeType}: $e';
        // ignore: avoid_print
        print('HARNESS search idle error: $e\n$st');
      }
    }

    // ======================================================================
    // 7. Library: unrelated single-tab emit frame cost (F-06)
    // ======================================================================
    final libraryCubit = getIt<LibraryCubit>();
    try {
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<PlayerCubit>.value(value: playerCubit),
            BlocProvider<SettingsCubit>.value(value: settingsCubit),
            BlocProvider<DynamicThemeCubit>.value(
              value: getIt<DynamicThemeCubit>(),
            ),
            BlocProvider<LibraryCubit>.value(value: libraryCubit),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AuraTheme.darkTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const LibraryScreen(),
          ),
        ),
      );
      await tester.pump();
      // Let the cubit's DB watches settle so state.songs is populated.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pump(const Duration(milliseconds: 16));

      // Emit touching only the Songs tab (new list instance, same content).
      for (int i = 0; i < 15; i++) {
        libraryCubit.emit(
          libraryCubit.state.copyWith(songs: List.of(libraryCubit.state.songs)),
        );
        metric('library_unrelated_emit_frame_us').add(await timePump());
      }
    } catch (e, st) {
      metric('library_unrelated_emit_frame_us').error = '${e.runtimeType}: $e';
      // ignore: avoid_print
      print('HARNESS library error: $e\n$st');
    }

    // ----------------------------------------------------------------------
    // Flush pending fake timers + close resources.
    // ----------------------------------------------------------------------
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(() async {
      await searchCubit.close();
      await libraryCubit.close();
      await playerCubit.close();
      await db.close();
    });

    // ----------------------------------------------------------------------
    // Report: table + JSON.
    // ----------------------------------------------------------------------
    // ignore: avoid_print
    print(
      '\n=== PULSR PERF HARNESS (host widget-test timings, microseconds) ===',
    );
    // ignore: avoid_print
    print(
      '${'metric'.padRight(38)} | ${'avg_us'.padLeft(10)} | ${'p95_us'.padLeft(10)} | ${'samples'.padLeft(7)}',
    );
    final jsonMetrics = <Map<String, dynamic>>[];
    for (final m in metrics.values) {
      if (m.samplesUs.isEmpty) {
        jsonMetrics.add({'id': m.id, 'error': m.error ?? 'no samples'});
        // ignore: avoid_print
        print('${m.id.padRight(38)} | ERROR: ${m.error}');
      } else {
        jsonMetrics.add({
          'id': m.id,
          'avg_us': m.avgUs,
          'p95_us': m.p95Us,
          'samples': m.samplesUs.length,
        });
        // ignore: avoid_print
        print(
          '${m.id.padRight(38)} | ${m.avgUs.toStringAsFixed(1).padLeft(10)} | ${m.p95Us.toStringAsFixed(1).padLeft(10)} | ${m.samplesUs.length.toString().padLeft(7)}',
        );
      }
    }
    // ignore: avoid_print
    print('==========================================================');

    final payload = {
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'flutter': Platform.version,
      'metrics': jsonMetrics,
    };

    final outDir = Directory('build/perf_metrics');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    final outFile = File('${outDir.path}/latest.json');
    outFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
    // ignore: avoid_print
    print('Wrote ${outFile.absolute.path}');

    // Sanity-only assertions: every recorded metric must be positive.
    for (final m in metrics.values) {
      if (m.samplesUs.isNotEmpty) {
        expect(
          m.avgUs,
          greaterThan(0),
          reason: '${m.id} recorded non-positive average',
        );
      }
    }
  });
}
