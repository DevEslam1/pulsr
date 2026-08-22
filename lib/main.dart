// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'core/config/app_config.dart';
import 'core/di/injection.dart';
import 'core/theme/aura_theme.dart';
import 'core/theme/dynamic_theme_cubit.dart';
import 'core/router/app_router.dart';
import 'core/services/file_intent_handler.dart';
import 'core/services/restore_detection_service.dart';
import 'core/utils/error_logger.dart';
import 'data/audio/audio_handler.dart';
import 'data/db/app_database.dart';
import 'data/repositories/music_repository.dart';
import 'data/scanner/media_scanner_service.dart';
import 'domain/repositories/music_repository_interface.dart';
import 'domain/usecases/get_songs_usecase.dart';
import 'domain/usecases/get_albums_usecase.dart';
import 'domain/usecases/get_artists_usecase.dart';
import 'domain/usecases/get_favorites_usecase.dart';
import 'domain/usecases/toggle_favorite_usecase.dart';
import 'domain/usecases/search_music_usecase.dart';
import 'domain/usecases/playlist_usecases.dart';
import 'domain/usecases/folder_usecases.dart';
import 'features/library/cubit/library_cubit.dart';
import 'features/player/cubit/player_cubit.dart';
import 'features/player/cubit/player_state.dart';
import 'features/playlists/cubit/playlist_cubit.dart';
import 'features/search/cubit/search_cubit.dart';
import 'features/settings/cubit/settings_cubit.dart';
import 'features/settings/cubit/settings_state.dart';
import 'features/widgets/widget_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorLogger.initialize();
  ErrorLogger.onCrashReported = (error, stackTrace, category) {
    // Production crash reporting hook (FirebaseCrashlytics / Sentry / Bugsnag)
    // FirebaseCrashlytics.instance.recordError(error, stackTrace, reason: category);
    debugPrint('[Pulsr.CrashReport][$category] $error\n$stackTrace');
  };

  // System Chrome configuration for true edge-to-edge UI
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  await configureDependencies();
  // Early registration of file intent handler so warm-start file opens are never dropped
  getIt<FileIntentHandler>();

  if (AppConfig.sentryDsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) {
        options.dsn = AppConfig.sentryDsn;
        options.environment = AppConfig.envName;
        options.tracesSampleRate = AppConfig.isProd ? 0.2 : 1.0;
        options.sendDefaultPii = false;
        options.enableAutoPerformanceTracing = true;
      },
      appRunner: () => runApp(const PulsrApp()),
    );
  } else {
    runApp(const PulsrApp());
  }
}

class PulsrApp extends StatefulWidget {
  const PulsrApp({super.key});

  @override
  State<PulsrApp> createState() => _PulsrAppState();
}

class _PulsrAppState extends State<PulsrApp> {
  late final _router = createRouter(getIt<MediaScannerService>());

  @override
  void initState() {
    super.initState();
    _autoScanOnStartup();
    _checkInitialAudioIntent();
  }

  void _checkInitialAudioIntent() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await getIt<FileIntentHandler>().checkInitialUri();
      } catch (e, st) {
        ErrorLogger.log('Failed to process initial audio intent on startup', error: e, stackTrace: st, category: 'Startup');
      }
    });
  }

  void _autoScanOnStartup() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final scanner = getIt<MediaScannerService>();
        await RestoreDetectionService.checkAndHandleRestore(scanner);
        final hasPermission = await scanner.checkPermission();
        if (hasPermission) {
          final settingsCubit = getIt<SettingsCubit>();
          await settingsCubit.rescanLibrary();
        }
      } catch (e, st) {
        ErrorLogger.log('Failed to execute automatic startup media scan', error: e, stackTrace: st, category: 'Startup');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppDatabase>.value(value: getIt<AppDatabase>()),
        RepositoryProvider<IMusicRepository>.value(value: getIt<IMusicRepository>()),
        RepositoryProvider<MusicRepository>.value(
            value: getIt<IMusicRepository>() as MusicRepository),
        RepositoryProvider<PulsrAudioHandler>.value(value: getIt<PulsrAudioHandler>()),
        RepositoryProvider<MediaScannerService>.value(
            value: getIt<MediaScannerService>()),
        RepositoryProvider<GetSongsUseCase>.value(
            value: getIt<GetSongsUseCase>()),
        RepositoryProvider<GetAlbumsUseCase>.value(
            value: getIt<GetAlbumsUseCase>()),
        RepositoryProvider<GetArtistsUseCase>.value(
            value: getIt<GetArtistsUseCase>()),
        RepositoryProvider<GetFavoritesUseCase>.value(
            value: getIt<GetFavoritesUseCase>()),
        RepositoryProvider<ToggleFavoriteUseCase>.value(
            value: getIt<ToggleFavoriteUseCase>()),
        RepositoryProvider<SearchMusicUseCase>.value(
            value: getIt<SearchMusicUseCase>()),
        RepositoryProvider<PlaylistUseCases>.value(
            value: getIt<PlaylistUseCases>()),
        RepositoryProvider<FolderUseCases>.value(value: getIt<FolderUseCases>()),
        RepositoryProvider<WidgetService>.value(value: getIt<WidgetService>()),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<DynamicThemeCubit>(
            create: (_) => getIt<DynamicThemeCubit>(),
          ),
          BlocProvider<PlayerCubit>(
            create: (ctx) {
              final cubit = getIt<PlayerCubit>();
              final song = cubit.state.currentSong;
              if (song != null) {
                getIt<DynamicThemeCubit>().updateFromSongId(song.id);
              }
              return cubit;
            },
          ),
          BlocProvider<LibraryCubit>(
            create: (_) => getIt<LibraryCubit>(),
          ),
          BlocProvider<SearchCubit>(
            create: (_) => getIt<SearchCubit>(),
          ),
          BlocProvider<PlaylistCubit>(
            create: (_) => getIt<PlaylistCubit>(),
          ),
          BlocProvider<SettingsCubit>(
            create: (_) => getIt<SettingsCubit>(),
          ),
        ],
        child: MultiBlocListener(
          listeners: [
            BlocListener<PlayerCubit, PlayerState>(
              listenWhen: (prev, curr) => prev.currentSong?.id != curr.currentSong?.id,
              listener: (context, state) {
                final song = state.currentSong;
                final isDynamicOn = context.read<SettingsCubit>().state.dynamicThemingEnabled;
                if (isDynamicOn) {
                  if (song != null) {
                    context.read<DynamicThemeCubit>().updateFromSongId(song.id);
                  } else {
                    context.read<DynamicThemeCubit>().resetToDefault();
                  }
                }
              },
            ),
            BlocListener<SettingsCubit, SettingsState>(
              listenWhen: (prev, curr) => prev.dynamicThemingEnabled != curr.dynamicThemingEnabled,
              listener: (context, state) {
                if (state.dynamicThemingEnabled) {
                  final song = context.read<PlayerCubit>().state.currentSong;
                  if (song != null) {
                    context.read<DynamicThemeCubit>().updateFromSongId(song.id);
                  }
                } else {
                  context.read<DynamicThemeCubit>().resetToDefault();
                }
              },
            ),
          ],
          child: BlocBuilder<SettingsCubit, SettingsState>(
            builder: (context, settingsState) {
              return BlocBuilder<DynamicThemeCubit, DynamicThemeState>(
                builder: (context, dynamicThemeState) {
                  final isDynamicOn = settingsState.dynamicThemingEnabled;
                  final activeAccent = isDynamicOn
                      ? dynamicThemeState.primaryColor
                      : settingsState.customAccentColor;

                  final lightTheme = AuraTheme.customTheme(
                    activeAccent,
                    brightness: Brightness.light,
                  );

                  final darkTheme = AuraTheme.customTheme(
                    activeAccent,
                    brightness: Brightness.dark,
                    isAmoled: settingsState.themeMode == AppThemeMode.amoled,
                  );

                  final ThemeMode flutterThemeMode;
                  switch (settingsState.themeMode) {
                    case AppThemeMode.light:
                      flutterThemeMode = ThemeMode.light;
                      break;
                    case AppThemeMode.dark:
                    case AppThemeMode.amoled:
                      flutterThemeMode = ThemeMode.dark;
                      break;
                    case AppThemeMode.system:
                      flutterThemeMode = ThemeMode.system;
                      break;
                  }

                  final isDarkTheme = flutterThemeMode == ThemeMode.dark ||
                      (flutterThemeMode == ThemeMode.system &&
                          WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);

                  return AnnotatedRegion<SystemUiOverlayStyle>(
                    value: SystemUiOverlayStyle(
                      statusBarColor: Colors.transparent,
                      statusBarIconBrightness: isDarkTheme ? Brightness.light : Brightness.dark,
                      systemNavigationBarColor: Colors.transparent,
                      systemNavigationBarIconBrightness: isDarkTheme ? Brightness.light : Brightness.dark,
                    ),
                    child: MaterialApp.router(
                      title: AppConfig.appTitle,
                      debugShowCheckedModeBanner: false,
                      themeMode: flutterThemeMode,
                      theme: lightTheme,
                      darkTheme: darkTheme,
                      routerConfig: _router,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
