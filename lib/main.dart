// lib/main.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'l10n/generated/app_localizations.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'core/config/app_config.dart';
import 'core/di/injection.dart';
import 'core/network/app_http_overrides.dart';
import 'core/theme/aura_theme.dart';
import 'core/theme/dynamic_theme_cubit.dart';
import 'core/router/app_router.dart';
import 'core/services/auth_service.dart';
import 'core/services/file_intent_handler.dart';
import 'core/services/restore_detection_service.dart';
import 'core/services/ytm_account_service.dart';
import 'core/services/ytm_service.dart';
import 'core/utils/error_logger.dart';
import 'core/utils/ytm_rate_limiter.dart';
import 'data/audio/audio_handler.dart';
import 'data/db/app_database.dart';
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
import 'features/auth/cubit/auth_cubit.dart';
import 'features/auth/presentation/ytm_web_login_sheet.dart';
import 'features/library/cubit/library_cubit.dart';
import 'features/player/cubit/player_cubit.dart';
import 'features/player/cubit/player_state.dart';
import 'features/playlists/cubit/playlist_cubit.dart';
import 'features/search/cubit/search_cubit.dart';
import 'features/settings/cubit/settings_cubit.dart';
import 'features/settings/cubit/settings_state.dart';
import 'features/widgets/widget_service.dart';
import 'features/ytm_search/cubit/ytm_download_cubit.dart';
import 'domain/repositories/download_repository_interface.dart';
import 'features/downloads/cubit/downloads_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = AppHttpOverrides.instance;
  try {
    AppConfig.validateConfiguration();
  } catch (e, st) {
    ErrorLogger.log('AppConfig.validateConfiguration error',
        error: e, stackTrace: st, category: 'Startup');
  }

  ErrorLogger.onCrashReported = (error, stackTrace, category) {
    // Production crash reporting hook (FirebaseCrashlytics / Sentry / Bugsnag)
    // FirebaseCrashlytics.instance.recordError(error, stackTrace, reason: category);
    debugPrint('[Pulsr.CrashReport][$category] $error\n$stackTrace');
  };
  ErrorLogger.initialize();

  // System Chrome configuration for true edge-to-edge UI
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    ),
  );

  try {
    await configureDependencies().timeout(const Duration(seconds: 15));
  } catch (e, st) {
    ErrorLogger.log('DI configureDependencies failed or timed out',
        error: e, stackTrace: st, category: 'Startup');
  }

  try {
    await YtmRateLimiter.shared.restore().timeout(const Duration(seconds: 8));
  } catch (e, st) {
    ErrorLogger.log('YtmRateLimiter restore failed or timed out',
        error: e, stackTrace: st, category: 'Startup');
  }

  try {
    await getIt<AuthService>().initialize().timeout(const Duration(seconds: 8));
  } catch (e, st) {
    ErrorLogger.log('AuthService initialize failed or timed out',
        error: e, stackTrace: st, category: 'Startup');
  }

  try {
    await getIt<YtmAccountService>().init().timeout(const Duration(seconds: 8));
  } catch (e, st) {
    ErrorLogger.log('YtmAccountService init failed or timed out',
        error: e, stackTrace: st, category: 'Startup');
  }

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
  late final GoRouter _router;
  StreamSubscription<void>? _authExpiredSub;
  DateTime? _lastAuthExpiredPrompt;

  @override
  void initState() {
    super.initState();
    _router = createRouter(getIt<MediaScannerService>());
    _autoScanOnStartup();
    _checkInitialAudioIntent();
    _listenForYtmSessionExpiry();
  }

  /// Surfaces a re-login prompt when the YouTube Music session dies mid-use
  /// (detected during stream resolution), instead of failing silently.
  void _listenForYtmSessionExpiry() {
    getIt.allReady().then((_) {
      if (!mounted) return;
      try {
        _authExpiredSub = getIt<YtmService>().onAuthExpired.listen((_) {
          if (!mounted) return;
          final now = DateTime.now();
          final last = _lastAuthExpiredPrompt;
          if (last != null && now.difference(last).inSeconds < 15) return;
          _lastAuthExpiredPrompt = now;

          final ctx = rootNavigatorKey.currentContext;
          if (ctx == null || !ctx.mounted) return;
          ScaffoldMessenger.of(ctx)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: const Text(
                    'YouTube Music session expired. Sign in again to keep streaming.'),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 6),
                action: SnackBarAction(
                  label: 'Sign In',
                  onPressed: () => YtmWebLoginSheet.show(ctx),
                ),
              ),
            );
        });
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _authExpiredSub?.cancel();
    super.dispose();
  }

  void _checkInitialAudioIntent() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await getIt<FileIntentHandler>().checkInitialUri();
      } catch (e, st) {
        if (!mounted) return;
        ErrorLogger.log('Failed to process initial audio intent on startup',
            error: e, stackTrace: st, category: 'Startup');
      }
    });
  }

  void _autoScanOnStartup() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final scanner = getIt<MediaScannerService>();
        await RestoreDetectionService.checkAndHandleRestore(scanner);
        if (!mounted) return;
        final hasPermission = await scanner.checkPermission();
        if (hasPermission && mounted) {
          final repo = getIt<IMusicRepository>();
          final songsRes = await repo.getAllSongs(limit: 1);
          final hasSongs = songsRes.fold((l) => false, (r) => r.isNotEmpty);
          if (!hasSongs && mounted) {
            final settingsCubit = getIt<SettingsCubit>();
            await settingsCubit.rescanLibrary();
          }
        }
      } catch (e, st) {
        if (!mounted) return;
        ErrorLogger.log('Failed to execute automatic startup media scan',
            error: e, stackTrace: st, category: 'Startup');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppDatabase>.value(value: getIt<AppDatabase>()),
        RepositoryProvider<IMusicRepository>.value(
            value: getIt<IMusicRepository>()),
        RepositoryProvider<PulsrAudioHandler>.value(
            value: getIt<PulsrAudioHandler>()),
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
        RepositoryProvider<FolderUseCases>.value(
            value: getIt<FolderUseCases>()),
        RepositoryProvider<WidgetService>.value(value: getIt<WidgetService>()),
        RepositoryProvider<IDownloadRepository>.value(
            value: getIt<IDownloadRepository>()),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<DynamicThemeCubit>(
            create: (_) => getIt<DynamicThemeCubit>(),
          ),
          BlocProvider<PlayerCubit>(
            create: (_) => getIt<PlayerCubit>(),
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
          BlocProvider<AuthCubit>(
            create: (_) => getIt<AuthCubit>(),
          ),
          BlocProvider<DownloadsCubit>(
            create: (_) => getIt<DownloadsCubit>(),
          ),
          if (AppConfig.ytmEnabled)
            BlocProvider<YtmDownloadCubit>(
              create: (_) => getIt<YtmDownloadCubit>(),
            ),
        ],
        child: MultiBlocListener(
          listeners: [
            BlocListener<PlayerCubit, PlayerState>(
              listenWhen: (prev, curr) =>
                  prev.currentSong?.id != curr.currentSong?.id,
              listener: (context, state) {
                final song = state.currentSong;
                final source =
                    context.read<SettingsCubit>().state.themeColorSource;
                // Keep the album-art palette fresh for the artwork source and
                // for system (used as the pre-Android-12 fallback seed).
                if (source == ThemeColorSource.artwork ||
                    source == ThemeColorSource.system) {
                  if (song != null) {
                    context.read<DynamicThemeCubit>().updateFromSong(song);
                  } else {
                    context.read<DynamicThemeCubit>().resetToDefault();
                  }
                }
              },
            ),
            BlocListener<SettingsCubit, SettingsState>(
              listenWhen: (prev, curr) =>
                  prev.themeColorSource != curr.themeColorSource,
              listener: (context, state) {
                final usesArt =
                    state.themeColorSource == ThemeColorSource.artwork ||
                        state.themeColorSource == ThemeColorSource.system;
                if (usesArt) {
                  final song = context.read<PlayerCubit>().state.currentSong;
                  if (song != null) {
                    context.read<DynamicThemeCubit>().updateFromSong(song);
                  }
                } else {
                  context.read<DynamicThemeCubit>().resetToDefault();
                }
              },
            ),
          ],
          child: BlocSelector<
              SettingsCubit,
              SettingsState,
              ({
                ThemeColorSource colorSource,
                AppThemeMode themeMode,
                Color customAccent,
                String languageCode
              })>(
            selector: (state) => (
              colorSource: state.themeColorSource,
              themeMode: state.themeMode,
              customAccent: state.customAccentColor,
              languageCode: state.languageCode,
            ),
            builder: (context, settingsConfig) {
              return BlocSelector<DynamicThemeCubit, DynamicThemeState,
                  ({Color primaryColor, bool hasCustomArtwork})>(
                selector: (state) => (
                  primaryColor: state.primaryColor,
                  hasCustomArtwork: state.hasCustomArtworkColor,
                ),
                builder: (context, dynamicThemeConfig) {
                  return DynamicColorBuilder(
                    builder: (lightDynamic, darkDynamic) {
                      // Resolve the accent seed per brightness.
                      Color resolveAccent(ColorScheme? dynamicScheme) {
                        switch (settingsConfig.colorSource) {
                          case ThemeColorSource.system:
                            if (dynamicScheme != null) {
                              return dynamicScheme.primary;
                            }
                            return dynamicThemeConfig.hasCustomArtwork
                                ? dynamicThemeConfig.primaryColor
                                : settingsConfig.customAccent;
                          case ThemeColorSource.artwork:
                            return dynamicThemeConfig.primaryColor;
                          case ThemeColorSource.custom:
                            return settingsConfig.customAccent;
                        }
                      }

                      final lightTheme = AuraTheme.customTheme(
                        resolveAccent(lightDynamic),
                        brightness: Brightness.light,
                      );

                      final darkTheme = AuraTheme.customTheme(
                        resolveAccent(darkDynamic),
                        brightness: Brightness.dark,
                        isAmoled:
                            settingsConfig.themeMode == AppThemeMode.amoled,
                      );

                      final ThemeMode flutterThemeMode;
                      switch (settingsConfig.themeMode) {
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
                              MediaQuery.platformBrightnessOf(context) ==
                                  Brightness.dark);

                      return AnnotatedRegion<SystemUiOverlayStyle>(
                        value: SystemUiOverlayStyle(
                          statusBarColor: Colors.transparent,
                          statusBarIconBrightness:
                              isDarkTheme ? Brightness.light : Brightness.dark,
                          systemNavigationBarColor: Colors.transparent,
                          systemNavigationBarIconBrightness:
                              isDarkTheme ? Brightness.light : Brightness.dark,
                        ),
                        child: MaterialApp.router(
                          title: AppConfig.appTitle,
                          debugShowCheckedModeBanner: false,
                          themeMode: flutterThemeMode,
                          theme: lightTheme,
                          darkTheme: darkTheme,
                          locale: settingsConfig.languageCode == 'system'
                              ? null
                              : Locale(settingsConfig.languageCode),
                          localizationsDelegates: const [
                            AppLocalizations.delegate,
                            GlobalMaterialLocalizations.delegate,
                            GlobalWidgetsLocalizations.delegate,
                            GlobalCupertinoLocalizations.delegate,
                          ],
                          supportedLocales: AppLocalizations.supportedLocales,
                          routerConfig: _router,
                        ),
                      );
                    },
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
