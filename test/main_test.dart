// test/main_test.dart
//
// Drives the real `main()` entrypoint under `flutter_test`.
//
// `main()` cannot run its native path in tests: Firebase/Sentry are absent and
// `configureDependencies()` eagerly builds singletons that need platform
// channels. This test therefore pre-seeds a hand-built DI graph (mirroring
// test/main_bootstrap_test.dart) and pre-registers `HttpClient` so the
// generated `getIt.init()` throws immediately. `main()` catches that and falls
// through to `runApp`, letting the bootstrap, env guards, error boundary and
// post-startup wiring execute hermetically.
import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart' show getIt;
import 'package:pulsr/core/services/auth_service.dart';
import 'package:pulsr/core/services/scrobbler_service.dart';
import 'package:pulsr/core/services/sound_feedback_service.dart';
import 'package:pulsr/core/theme/dynamic_theme_cubit.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';
import 'package:pulsr/data/repositories/smart_playlist_engine.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/repositories/download_repository_interface.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/domain/usecases/delete_download.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/domain/usecases/get_albums_usecase.dart';
import 'package:pulsr/domain/usecases/get_artists_usecase.dart';
import 'package:pulsr/domain/usecases/get_download_storage_stats.dart';
import 'package:pulsr/domain/usecases/get_favorites_usecase.dart';
import 'package:pulsr/domain/usecases/get_genres_usecase.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/domain/usecases/get_years_usecase.dart';
import 'package:pulsr/domain/usecases/observe_downloads.dart';
import 'package:pulsr/domain/usecases/pause_download.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/domain/usecases/queue_download.dart';
import 'package:pulsr/domain/usecases/resume_download.dart';
import 'package:pulsr/domain/usecases/retry_download.dart';
import 'package:pulsr/domain/usecases/search_music_usecase.dart';
import 'package:pulsr/domain/usecases/toggle_favorite_usecase.dart';
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/playlists/cubit/playlist_cubit.dart';
import 'package:pulsr/features/search/cubit/search_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/widgets/widget_service.dart';
import 'package:pulsr/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/test_pulsr_audio_handler.dart';

class _MockDownloadRepo extends Mock implements IDownloadRepository {}

class _MockScrobblerService extends Mock implements ScrobblerService {}

class _MockAuthService extends Mock implements AuthService {}

/// Exposes the `platformBridgeDegraded` notifier that [TestPulsrAudioHandler]
/// satisfies only through `noSuchMethod`, so the degraded-bridge branch in
/// `_watchPlatformBridgeHealth`/`dispose` can be exercised.
class _BridgeAwareAudioHandler extends TestPulsrAudioHandler {
  final ValueNotifier<bool> _bridgeDegraded = ValueNotifier<bool>(false);

  @override
  ValueNotifier<bool> get platformBridgeDegraded => _bridgeDegraded;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'main() bootstraps, builds PulsrApp and runs post-startup tasks',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final channel in const [
        'com.pulsr.music/hires_dac',
        'com.pulsr.music/hires_dac_events',
        'com.pulsr.music/proxy',
        'dev.fluttercommunity.plus/connectivity_status',
        'com.pulsr.music/purity',
      ]) {
        messenger.setMockMethodCallHandler(
            MethodChannel(channel), (_) async => null);
      }
      messenger.setMockMethodCallHandler(
          SystemChannels.platform, (_) async => null);

      SharedPreferences.setMockInitialValues({});
      await getIt.reset();

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repo = MusicRepository(db);
      final smartEngine = SmartPlaylistEngine(db);
      final audioHandler = _BridgeAwareAudioHandler();
      final scannerService = MediaScannerService(repo);
      final httpClient = HttpClient();

      // Pre-registering `HttpClient` (the first registration the generated
      // graph performs) makes `configureDependencies()` throw before it can
      // instantiate any channel-bound singleton. `main()` catches that.
      getIt.registerSingleton<HttpClient>(httpClient);
      getIt.registerSingleton<AppDatabase>(db);
      getIt.registerSingleton<IMusicRepository>(repo);
      getIt.registerSingleton<MusicRepository>(repo);
      getIt.registerSingleton<PulsrAudioHandler>(audioHandler);
      getIt.registerSingleton<MediaScannerService>(scannerService);
      getIt.registerSingleton<GetSongsUseCase>(GetSongsUseCase(repo));
      getIt.registerSingleton<GetAlbumsUseCase>(GetAlbumsUseCase(repo));
      getIt.registerSingleton<GetArtistsUseCase>(GetArtistsUseCase(repo));
      getIt.registerSingleton<GetGenresUseCase>(GetGenresUseCase(repo));
      getIt.registerSingleton<GetYearsUseCase>(GetYearsUseCase(repo));
      getIt.registerSingleton<GetFavoritesUseCase>(GetFavoritesUseCase(repo));
      getIt.registerSingleton<ToggleFavoriteUseCase>(
          ToggleFavoriteUseCase(repo));
      getIt.registerSingleton<SearchMusicUseCase>(SearchMusicUseCase(repo));
      getIt.registerSingleton<PlaylistUseCases>(
          PlaylistUseCases(repo, smartEngine));
      getIt.registerSingleton<FolderUseCases>(FolderUseCases(repo));
      getIt.registerSingleton<WidgetService>(WidgetService());

      final mockDownloadRepo = _MockDownloadRepo();
      when(() => mockDownloadRepo.observeDownloads())
          .thenAnswer((_) => const Stream.empty());
      when(() => mockDownloadRepo.getAllDownloads())
          .thenAnswer((_) async => []);
      when(() => mockDownloadRepo.getStorageStats())
          .thenAnswer((_) async => const Right(StorageStats()));
      final mockAuth = _MockAuthService();
      when(() => mockAuth.initialize()).thenAnswer((_) async {});
      getIt.registerSingleton<AuthService>(mockAuth);

      final mockScrobbler = _MockScrobblerService();
      when(() => mockScrobbler.migrateAllCredentialsToSecureStorage())
          .thenAnswer((_) async {});
      when(() => mockScrobbler.checkPendingScrobble()).thenAnswer((_) async {});
      getIt.registerSingleton<ScrobblerService>(mockScrobbler);

      getIt.registerSingleton<IDownloadRepository>(mockDownloadRepo);
      getIt.registerSingleton<DownloadsCubit>(DownloadsCubit(
        QueueDownloadUseCase(mockDownloadRepo),
        PauseDownloadUseCase(mockDownloadRepo),
        ResumeDownloadUseCase(mockDownloadRepo),
        RetryDownloadUseCase(mockDownloadRepo),
        DeleteDownloadUseCase(mockDownloadRepo),
        ObserveDownloadsUseCase(mockDownloadRepo),
        GetDownloadStorageStatsUseCase(mockDownloadRepo),
      ));

      getIt.registerSingleton<DynamicThemeCubit>(DynamicThemeCubit());
      getIt.registerFactory<PlayerCubit>(() => PlayerCubit(
            audioHandler: audioHandler,
            repository: repo,
            toggleFavoriteUseCase: ToggleFavoriteUseCase(repo),
          ));
      getIt.registerFactory<LibraryCubit>(() => LibraryCubit(
            getSongsUseCase: GetSongsUseCase(repo),
            getAlbumsUseCase: GetAlbumsUseCase(repo),
            getArtistsUseCase: GetArtistsUseCase(repo),
            getGenresUseCase: GetGenresUseCase(repo),
            getYearsUseCase: GetYearsUseCase(repo),
            getFavoritesUseCase: GetFavoritesUseCase(repo),
            toggleFavoriteUseCase: ToggleFavoriteUseCase(repo),
            folderUseCases: FolderUseCases(repo),
          ));
      getIt.registerFactory<SearchCubit>(() => SearchCubit(
            searchUseCase: SearchMusicUseCase(repo),
            folderUseCases: FolderUseCases(repo),
          ));
      getIt.registerFactory<PlaylistCubit>(() =>
          PlaylistCubit(playlistUseCases: PlaylistUseCases(repo, smartEngine)));
      getIt.registerSingleton<SettingsCubit>(
          SettingsCubit(scannerService: scannerService));

      // `main()` installs its own ErrorWidget.builder / FlutterError.onError.
      // Restore the test binding's handlers afterwards so the framework's
      // invariant checks and error capture keep working.
      final originalErrorWidgetBuilder = ErrorWidget.builder;
      final originalFlutterErrorOnError = FlutterError.onError;

      await tester.runAsync(() async {
        await app.main();
      });

      final mainErrorWidgetBuilder = ErrorWidget.builder;
      ErrorWidget.builder = originalErrorWidgetBuilder;
      FlutterError.onError = originalFlutterErrorOnError;

      await tester.pump();
      expect(find.byType(app.PulsrApp), findsOneWidget);

      // main() installs this callback; invoking it exercises the audio-handler
      // probe branch.
      expect(SoundFeedbackService.isMusicPlaying?.call(), isFalse);

      // The degraded-bridge listener was registered at init; flipping it fires
      // the surface() branch while the router is mounted.
      audioHandler.platformBridgeDegraded.value = true;
      await tester.pump();

      // Lifecycle branches reached from the mounted root.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.detached);
      await tester.pump();
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // ignore: invalid_use_of_protected_member
      tester.binding.handleMemoryPressure();
      await tester.pump();

      // Landscape drives the system-UI observer branch.
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pump();
      tester.view.physicalSize = const Size(900, 1600);
      await tester.pump();

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      // Exercise the global ErrorWidget.builder installed by main().
      await tester.pumpWidget(MaterialApp(
        home: mainErrorWidgetBuilder(
          FlutterErrorDetails(exception: StateError('boom')),
        ),
      ));
      await tester.pump();

      await audioHandler.dispose();
      await db.close();
      httpClient.close(force: true);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
