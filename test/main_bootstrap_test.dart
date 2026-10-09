// test/main_bootstrap_test.dart
//
// Mounts the real [PulsrApp] root with a hand-built DI graph (mirroring
// test/integration/widget_test.dart) to exercise the bootstrap/lifecycle
// branches in lib/main.dart that the async `main()` entry cannot reach under
// `flutter_test` (it performs Firebase/Sentry/DI platform work and calls
// runApp). Platform channels are stubbed so the mount is hermetic.
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart' show getIt;
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
import 'package:pulsr/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/test_pulsr_audio_handler.dart';

class _MockDownloadRepo extends Mock implements IDownloadRepository {}

void main() {
  setUp(() async {
    await getIt.reset();
  });

  testWidgets('PulsrApp bootstraps and drives lifecycle branches',
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
      messenger.setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }

    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = MusicRepository(db);
    final smartEngine = SmartPlaylistEngine(db);
    final audioHandler = TestPulsrAudioHandler();
    final scannerService = MediaScannerService(repo);

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
    getIt.registerSingleton<ToggleFavoriteUseCase>(ToggleFavoriteUseCase(repo));
    getIt.registerSingleton<SearchMusicUseCase>(SearchMusicUseCase(repo));
    getIt.registerSingleton<PlaylistUseCases>(PlaylistUseCases(repo, smartEngine));
    getIt.registerSingleton<FolderUseCases>(FolderUseCases(repo));
    getIt.registerSingleton<WidgetService>(WidgetService());

    final mockDownloadRepo = _MockDownloadRepo();
    when(() => mockDownloadRepo.observeDownloads())
        .thenAnswer((_) => const Stream.empty());
    when(() => mockDownloadRepo.getAllDownloads()).thenAnswer((_) async => []);
    when(() => mockDownloadRepo.getStorageStats())
        .thenAnswer((_) async => const Right(StorageStats()));
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
    getIt.registerFactory<PlaylistCubit>(
        () => PlaylistCubit(playlistUseCases: PlaylistUseCases(repo, smartEngine)));
    getIt.registerSingleton<SettingsCubit>(
        SettingsCubit(scannerService: scannerService));

    await tester.runAsync(() async {
      await tester.pumpWidget(const PulsrApp());
      await tester.pump();
      expect(find.byType(PulsrApp), findsOneWidget);

      // Paused / detached flush the debounced queue-slot write.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // Memory-pressure branch trims artwork caches.
      // ignore: invalid_use_of_protected_member
      tester.binding.handleMemoryPressure();
      await tester.pump();

      // Landscape orientation branch drives the system UI observer.
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
    });

    await audioHandler.dispose();
    await db.close();
  });
}
