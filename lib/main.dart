// lib/main.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'core/errors/error_message_resolver.dart';
import 'core/utils/l10n_extensions.dart';
import 'package:flutter/services.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n/generated/app_localizations.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/performance/gpu_budget.dart';
import 'core/utils/platform_capabilities.dart';
import 'core/config/app_config.dart';
import 'core/di/injection.dart';
import 'core/network/app_http_overrides.dart';
import 'core/services/artwork_cache_manager.dart';
import 'core/services/automation_trigger_service.dart';
import 'core/theme/aura_theme.dart';
import 'core/theme/dynamic_theme_cubit.dart';
import 'core/widgets/cached_artwork.dart';
import 'core/widgets/pulsr_toast.dart';
import 'core/router/app_router.dart';
import 'core/network/network_change_monitor.dart';
import 'core/services/auth_service.dart';
import 'core/services/scrobbler_service.dart';
import 'core/services/file_intent_handler.dart';
import 'core/services/restore_detection_service.dart';
import 'core/services/ytm_account_service.dart';
import 'core/services/ytm_service.dart';
import 'core/services/ytm_url_cache.dart';
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
    // Crashlytics is not a dependency — Sentry is the crash backend.
    // Route every crash report there (when telemetry is allowed) plus logcat.
    try {
      if (AppConfig.isTelemetryAllowed) {
        Sentry.captureException(error, stackTrace: stackTrace);
      }
    } catch (_) {}
    debugPrint('[Pulsr.CrashReport][$category] $error\n$stackTrace');
  };
  ErrorLogger.initialize();

  // Rehydrate the GPU budget before first frame (persisted by SettingsCubit).
  try {
    final prefs = await SharedPreferences.getInstance();
    GpuBudget.setEnabled(prefs.getBool('setting_reduce_motion') ?? false);
  } catch (_) {}
  // Warm native audio capability cache (best-effort, never blocks).
  unawaited(PlatformCapabilities.ensureLoaded()
      .timeout(const Duration(seconds: 5))
      .catchError((_) {}));

  // Firebase powers Auth + (optionally) cloud sync. Pure builds must perform
  // zero network work, so skip init there; elsewhere init best-effort so a
  // missing google-services file never blocks startup.
  if (!AppConfig.isPure) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 8));
    } catch (e, st) {
      ErrorLogger.log('Firebase.initializeApp failed — Auth runs offline-only',
          error: e, stackTrace: st, category: 'Startup');
    }
  }

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

  // Defer heavy post-DI tasks to AFTER runApp to eliminate Davey! 1223ms jank on OnePlus
  // Previously awaited 3x8s before first frame -> Skipped 121 frames. Now fire-and-forget.
  void firePostStartupTasks() {
    // Run in next microtask so first frame draws before any I/O
    Future.microtask(() async {
      // Respect the user's offline-only setting at cold start: it must disable
      // every online initializer, not just the UI surfaces (mirrors
      // CloudSyncService's runtime gate).
      var offlineOnly = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        offlineOnly = prefs.getBool('setting_offline_only_mode') ?? false;
      } catch (_) {}
      final onlineAllowed = AppConfig.ytmEnabled && !offlineOnly;
      try {
        await Future.wait([
          // Pure builds have no INTERNET permission: skip every online
          // initializer so Pulsr Pure performs zero network work at startup.
          if (onlineAllowed)
            YtmRateLimiter.shared.restore().timeout(const Duration(seconds: 8)).catchError((e, st) {
              ErrorLogger.log('YtmRateLimiter restore failed or timed out',
                  error: e, stackTrace: st, category: 'Startup');
            }),
          if (AppConfig.isCloudSyncAllowed && !offlineOnly)
            getIt<AuthService>().initialize().timeout(const Duration(seconds: 8)).catchError((e, st) {
              ErrorLogger.log('AuthService initialize failed or timed out',
                  error: e, stackTrace: st, category: 'Startup');
            }),
          if (onlineAllowed)
            getIt<YtmAccountService>().init().timeout(const Duration(seconds: 8)).catchError((e, st) {
              ErrorLogger.log('YtmAccountService init failed or timed out',
                  error: e, stackTrace: st, category: 'Startup');
            }),
          // Rehydrate guest stream URLs saved by the previous run so a replay
          // or skip-back after launch resolves instantly.
          if (onlineAllowed && getIt.isRegistered<YtmUrlCache>())
            getIt<YtmUrlCache>().restore().timeout(const Duration(seconds: 8)).catchError((e, st) {
              ErrorLogger.log('YtmUrlCache restore failed or timed out',
                  error: e, stackTrace: st, category: 'Startup');
            }),
        ]);
        // Warm the native extractor (BotGuard WebView + client matrix) while
        // the user is still looking at the home screen, so the first YTM
        // search/tap doesn't pay cold-start attestation (~seconds).
        // Fire-and-forget, guarded: never blocks or throws into startup.
        try {
          if (onlineAllowed && getIt.isRegistered<YtmService>()) {
            unawaited(getIt<YtmService>()
                .preWarm()
                .timeout(const Duration(seconds: 15))
                .catchError((_) {}));
          }
        } catch (_) {}
        // Scrobbler session recovery + credential migration (previously only
        // reachable from tests): recover a scrobble interrupted by process
        // death, and proactively move leftover plaintext credentials into
        // secure storage. Local-first; safe to run whenever cloud sync is on.
        try {
          if (AppConfig.isCloudSyncAllowed &&
              !offlineOnly &&
              getIt.isRegistered<ScrobblerService>()) {
            final scrobbler = getIt<ScrobblerService>();
            unawaited(scrobbler
                .migrateAllCredentialsToSecureStorage()
                .then((_) => scrobbler.checkPendingScrobble())
                .timeout(const Duration(seconds: 10))
                .catchError((e, st) {
              ErrorLogger.log('Scrobbler startup recovery failed',
                  error: e, stackTrace: st, category: 'Startup');
            }));
          }
        } catch (e, st) {
          ErrorLogger.log('Scrobbler startup hook failed',
              error: e, stackTrace: st, category: 'Startup');
        }
      } catch (e, st) {
        ErrorLogger.log('Parallel startup init failed',
            error: e, stackTrace: st, category: 'Startup');
      }
    });
  }

  if (AppConfig.isTelemetryAllowed) {
    await SentryFlutter.init(
      (options) {
        options.dsn = AppConfig.sentryDsn;
        options.environment = AppConfig.envName;
        options.tracesSampleRate = AppConfig.isProd ? 0.2 : 1.0;
        options.sendDefaultPii = false;
        options.enableAutoPerformanceTracing = true;
      },
      appRunner: () {
        runApp(const PulsrApp());
        firePostStartupTasks();
      },
    );
  } else {
    runApp(const PulsrApp());
    firePostStartupTasks();
  }
}

class PulsrApp extends StatefulWidget {
  const PulsrApp({super.key});

  @override
  State<PulsrApp> createState() => _PulsrAppState();
}

class _PulsrAppState extends State<PulsrApp> with WidgetsBindingObserver {
  late final GoRouter _router;
  StreamSubscription<void>? _authExpiredSub;
  StreamSubscription<void>? _networkChangeSub;
  NetworkChangeMonitor? _networkMonitor;
  AutomationTriggerService? _automationTriggerService;
  VoidCallback? _platformBridgeDegradedListener;
  DateTime? _lastAuthExpiredPrompt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _router = createRouter(getIt<MediaScannerService>());
    _autoScanOnStartup();
    _checkInitialAudioIntent();
    if (AppConfig.ytmEnabled) _listenForYtmSessionExpiry();
    if (AppConfig.isCloudSyncAllowed) _startNetworkChangeMonitor();
    _startAutomationTriggers();
    _watchPlatformBridgeHealth();
    _verifyPureMode();
  }

  /// Runtime "Pulsr Pure" guarantee: a Pure build must not carry the INTERNET
  /// permission. Ask the platform whether the merged manifest really omits it,
  /// and surface a loud error if a bad merge silently added network access.
  void _verifyPureMode() {
    if (!AppConfig.isPure) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final pure = await AppConfig.verifyPureNoInternet();
        if (pure == false) {
          ErrorLogger.log(
            'CRITICAL: Pulsr Pure build has INTERNET permission — purity check failed',
            category: 'Startup',
          );
          if (!mounted) return;
          final ctx = rootNavigatorKey.currentContext;
          if (ctx != null && ctx.mounted) {
            PulsrToast.show(
              ctx,
              message:
                  'Pulsr Pure integrity check failed: this build can access the network.',
              icon: Icons.warning_amber_rounded,
              isError: true,
              duration: const Duration(seconds: 6),
            );
          }
        }
      } catch (e, st) {
        ErrorLogger.log('Pulsr Pure verification failed',
            error: e, stackTrace: st, category: 'Startup');
      }
    });
  }

  /// B-6: if the platform audio bridge failed to initialise, playback still
  /// works but the lock-screen / shade controls silently do not exist. Surface
  /// it once so the user is not left wondering where the media notification is.
  void _watchPlatformBridgeHealth() {
    try {
      if (!getIt.isRegistered<PulsrAudioHandler>()) return;
      final handler = getIt<PulsrAudioHandler>();
      void surface() {
        if (!handler.platformBridgeDegraded.value) return;
        final ctx = rootNavigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        PulsrToast.show(
          ctx,
          message:
              'Background media controls are unavailable on this launch. '
              'Playback works, but the lock-screen controls could not start.',
          icon: Icons.warning_amber_rounded,
          isError: true,
          duration: const Duration(seconds: 5),
        );
      }

      if (handler.platformBridgeDegraded.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) => surface());
      } else {
        handler.platformBridgeDegraded.addListener(surface);
        _platformBridgeDegradedListener = surface;
      }
    } catch (e, st) {
      // Best-effort diagnostic only; never let it block startup (e.g. a test
      // double of the handler that does not expose the notifier).
      ErrorLogger.log('Failed to watch platform bridge health',
          error: e, stackTrace: st, category: 'Startup');
    }
  }

  /// Watches output-device changes (Bluetooth/headphones) and fires the
  /// matching user automation rules. Charging is intentionally not wired: it
  /// is not reliably observable from Dart without a native change.
  void _startAutomationTriggers() {
    try {
      final service = AutomationTriggerService();
      _automationTriggerService = service;
      service.start();
    } catch (e, st) {
      ErrorLogger.log('Failed to start automation trigger service',
          error: e, stackTrace: st, category: 'Startup');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // No-op: locale is stable; avoid AssetManager thrash (LOG-16)
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Flush the debounced queue-slot write before the process can be killed.
      try {
        if (getIt.isRegistered<PlayerCubit>()) {
          unawaited(getIt<PlayerCubit>().persistQueueSlotsNow());
        }
      } catch (_) {}
    }
  }

  @override
  void didHaveMemoryPressure() {
    // Trim artwork and stream caches on GC pressure (LOG-14 14MB/59MB)
    try {
      getIt<ArtworkCacheManager>().clearAllCache();
    } catch (_) {}
    try {
      // ignore: avoid_dynamic_calls
      (getIt.get<ArtworkLruCache>() as dynamic)?.trimForMemoryPressure();
    } catch (_) {
      // Fallback direct trim
      try { ArtworkLruCache().trimForMemoryPressure(); } catch (_) {}
    }
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
                content: Text(context.l10n.ytmSessionExpired),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 6),
                action: SnackBarAction(
                  label: ctx.l10n.signIn,
                  onPressed: () => YtmWebLoginSheet.show(ctx),
                ),
              ),
            );
        });
      } catch (_) {}
    });
  }

  void _startNetworkChangeMonitor() {
    getIt.allReady().then((_) {
      if (!mounted) return;
      try {
        final monitor = NetworkChangeMonitor();
        _networkMonitor = monitor;
        monitor.start();
        _networkChangeSub = monitor.onNetworkChanged.listen((_) async {
          debugPrint('[PulsrApp] Network path changed — invalidating YTM caches');
          try {
            if (getIt.isRegistered<YtmService>()) {
              await getIt<YtmService>().handleNetworkChange();
            }
          } catch (_) {}
          try {
            if (getIt.isRegistered<PulsrAudioHandler>()) {
              getIt<PulsrAudioHandler>().clearNetworkCaches();
            }
          } catch (_) {}
        });
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authExpiredSub?.cancel();
    _networkChangeSub?.cancel();
    _networkMonitor?.dispose();
    _automationTriggerService?.dispose();
    if (_platformBridgeDegradedListener != null &&
        getIt.isRegistered<PulsrAudioHandler>()) {
      getIt<PulsrAudioHandler>()
          .platformBridgeDegraded
          .removeListener(_platformBridgeDegradedListener!);
    }
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
          // getIt singletons are provided by value: `create:` would make the
          // provider close the shared instance on teardown, leaving getIt
          // handing out a dead cubit for the rest of the process.
          BlocProvider<DynamicThemeCubit>.value(
            value: getIt<DynamicThemeCubit>(),
          ),
          BlocProvider<PlayerCubit>.value(
            value: getIt<PlayerCubit>(),
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
          BlocProvider<SettingsCubit>.value(
            value: getIt<SettingsCubit>(),
          ),
          BlocProvider<AuthCubit>(
            create: (_) => getIt<AuthCubit>(),
          ),
          BlocProvider<DownloadsCubit>.value(
            value: getIt<DownloadsCubit>(),
          ),
          if (AppConfig.ytmEnabled)
            BlocProvider<YtmDownloadCubit>.value(
              value: getIt<YtmDownloadCubit>(),
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
            // App-level surface for transport failures: PlayerCubit writes the
            // message to PlayerState.errorMessage, so without this every
            // seek/skip/shuffle/repeat failure would be silent (A-10).
            BlocListener<PlayerCubit, PlayerState>(
              listenWhen: (prev, curr) =>
                  curr.errorMessage != null &&
                  curr.errorMessage != prev.errorMessage,
              listener: (context, state) {
                final message = state.errorMessage;
                if (message != null) {
                  // rootNavigatorKey.currentContext is the Navigator itself,
                  // whose Overlay is a *child* — Overlay.of(navigatorContext)
                  // throws. Use the overlay's own context instead.
                  final overlayCtx =
                      rootNavigatorKey.currentState?.overlay?.context;
                  if (overlayCtx != null && overlayCtx.mounted) {
                    PulsrToast.show(
                      overlayCtx,
                      message:
                          resolveUiErrorMessage(context, message),
                      icon: Icons.error_outline_rounded,
                      isError: true,
                    );
                  }
                }
                context.read<PlayerCubit>().clearError();
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
                String languageCode,
                bool highContrast,
                bool reduceMotion
              })>(
            selector: (state) => (
              colorSource: state.themeColorSource,
              themeMode: state.themeMode,
              customAccent: state.customAccentColor,
              languageCode: state.languageCode,
              highContrast: state.highContrast,
              reduceMotion: state.reduceMotion,
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
                      Color resolveAccent(Color? dynamicPrimary) {
                        switch (settingsConfig.colorSource) {
                          case ThemeColorSource.system:
                            if (dynamicPrimary != null) {
                              return dynamicPrimary;
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

                      final isHighContrast = settingsConfig.highContrast ||
                          MediaQuery.highContrastOf(context);
                      final isBoldText = MediaQuery.boldTextOf(context);

                      final lightTheme = isHighContrast
                          ? AuraTheme.highContrastThemeFor(Brightness.light,
                              seed: resolveAccent(lightDynamic?.primary))
                          : AuraTheme.customTheme(
                              resolveAccent(lightDynamic?.primary),
                              brightness: Brightness.light,
                              isBoldText: isBoldText,
                            );

                      final darkTheme = isHighContrast
                          ? AuraTheme.highContrastThemeFor(Brightness.dark,
                              seed: resolveAccent(darkDynamic?.primary))
                          : AuraTheme.customTheme(
                              resolveAccent(darkDynamic?.primary),
                              brightness: Brightness.dark,
                              isAmoled: settingsConfig.themeMode ==
                                  AppThemeMode.amoled,
                              isBoldText: isBoldText,
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

                      final isDarkTheme = isHighContrast ||
                          flutterThemeMode == ThemeMode.dark ||
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
                          builder: (context, child) {
                            // Honour both the in-app toggle and the OS
                            // "Reduce motion" / "Remove animations" setting.
                            // Overriding `disableAnimations` here makes every
                            // `PulsrMotion` call site collapse app-wide without
                            // each widget reading settings directly.
                            final media = MediaQuery.of(context);
                            final reduceMotion = settingsConfig.reduceMotion ||
                                media.disableAnimations;
                            return MediaQuery(
                              data: media.copyWith(
                                disableAnimations: reduceMotion,
                              ),
                              child: MediaQuery.withClampedTextScaling(
                                // Accessibility: allow the full OS text-size
                                // range (up to 200%). Fixed-height text boxes
                                // on key surfaces scale via
                                // MediaQuery.textScalerOf so nothing clips.
                                minScaleFactor: 0.8,
                                maxScaleFactor: 2.0,
                                child: child ?? const SizedBox.shrink(),
                              ),
                            );
                          },
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
