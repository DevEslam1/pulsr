// lib/main.dart
import 'dart:async';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'core/errors/error_message_resolver.dart';
import 'core/utils/l10n_extensions.dart';
import 'core/utils/l10n_holder.dart';
import 'core/utils/startup_gates.dart';
import 'package:flutter/services.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations, GlobalCupertinoLocalizations;
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n/generated/app_localizations.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/performance/gpu_budget.dart';
import 'core/utils/platform_capabilities.dart';
import 'core/config/app_config.dart';
import 'core/constants/app_typography.dart';
import 'core/di/injection.dart';
import 'core/network/app_http_overrides.dart';
import 'core/services/artwork_cache_manager.dart';
import 'core/services/settings_cache.dart';
import 'core/services/sound_feedback_service.dart';
import 'core/services/automation_trigger_service.dart';
import 'core/bloc/pulsr_bloc_observer.dart';
import 'core/constants/app_colors.dart';
import 'core/constants/app_radii.dart';
import 'core/constants/prefs_keys.dart';
import 'core/utils/pulsr_haptics.dart';
import 'core/theme/aura_theme.dart';
import 'core/theme/dynamic_theme_cubit.dart';
import 'core/theme/pulsr_button_style.dart';
import 'core/widgets/cached_artwork.dart';
import 'core/widgets/pulsr_toast.dart';
import 'core/router/app_router.dart';
import 'core/network/network_change_monitor.dart';
import 'core/services/auth_service.dart';
import 'core/services/scrobbler_service.dart';
import 'data/services/cast_service.dart';
import 'data/services/hires_audio_service.dart';
import 'data/services/usb_exclusive_service.dart';
import 'core/services/file_intent_handler.dart';
import 'core/services/restore_detection_service.dart';
import 'core/services/ytm_account_service.dart';
import 'core/services/ytm_client_version_resolver.dart';
import 'core/services/ytm_service.dart';
import 'core/services/ytm_url_cache.dart';
import 'core/utils/error_logger.dart';
import 'core/utils/ytm_rate_limiter.dart';
import 'data/audio/audio_handler.dart';
import 'data/audio/eq_legacy_migration.dart';
import 'features/audio_profiles/audio_profile_bootstrap.dart';
import 'features/audio_profiles/audio_profile_service.dart';
import 'data/db/app_database.dart';
import 'data/party/listen_together_service.dart';
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
import 'features/player/presentation/widgets/audio_visualizer.dart';
import 'features/playlists/cubit/playlist_cubit.dart';
import 'features/search/cubit/search_cubit.dart';
import 'features/settings/cubit/settings_cubit.dart';
import 'features/settings/cubit/settings_state.dart';
import 'features/widgets/widget_service.dart';
import 'features/ytm_search/cubit/ytm_download_cubit.dart';
import 'domain/repositories/download_repository_interface.dart';
import 'features/downloads/cubit/downloads_cubit.dart';
import 'features/announcements/announcement_settings.dart';
import 'features/announcements/track_announcer.dart';
import 'features/announcements/tts_engine.dart';
import 'features/assistant/assistant_intent_bootstrap.dart';
import 'features/assistant/assistant_settings.dart';
import 'features/assistant/assistant_suggestion_sync.dart';
import 'features/dlna/dlna_renderer_service.dart';
import 'features/extras/remote_playback_runtime.dart';
import 'features/system_behavior/system_behavior_runtime.dart';
import 'features/system_behavior/system_behavior_settings.dart';
import 'features/usb_tools/usb_ergonomics_service.dart';
import 'features/usb_tools/usb_quirk_store.dart';
import 'services/discord/discord_rpc_service.dart';
import 'services/updater/app_update_service.dart';
import 'services/updater/update_dialog.dart';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';

/// Readiness helper for DI singletons. `isRegistered` is already true while a
/// lazy async singleton is still pending, so a plain `getIt<T>()` can throw
/// "not ready yet" during startup.
bool _isDependencyReady<T extends Object>() {
  if (!getIt.isRegistered<T>()) return false;
  try {
    return getIt.isReadySync<T>();
  } on ArgumentError {
    // Sync singletons and factories are ready by definition.
    return true;
  } catch (_) {
    return false;
  }
}

/// Returns the instance immediately when it is ready, otherwise waits for the
/// pending async singleton instead of throwing.
Future<T> _resolveDependency<T extends Object>() {
  if (_isDependencyReady<T>()) return Future<T>.value(getIt<T>());
  return getIt.getAsync<T>();
}

bool _startupUpdateDialogShown = false;

void _surfaceStartupUpdate(UpdateInfo info) {
  if (_startupUpdateDialogShown) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_startupUpdateDialogShown) return;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final router = GoRouter.maybeOf(ctx);
    if (router == null) {
      _startupUpdateDialogShown = true;
      unawaited(UpdateDialog.show(ctx, info));
      return;
    }
    bool isTransientRoute(String path) =>
        path == '/splash' || path == '/onboarding';
    final currentPath = router.routerDelegate.currentConfiguration.uri.path;
    if (!isTransientRoute(currentPath)) {
      _startupUpdateDialogShown = true;
      unawaited(UpdateDialog.show(ctx, info));
      return;
    }
    late final VoidCallback listener;
    listener = () {
      if (_startupUpdateDialogShown) {
        router.routerDelegate.removeListener(listener);
        return;
      }
      final nextPath = router.routerDelegate.currentConfiguration.uri.path;
      if (isTransientRoute(nextPath)) return;
      router.routerDelegate.removeListener(listener);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_startupUpdateDialogShown) return;
        final navCtx = rootNavigatorKey.currentContext;
        if (navCtx == null || !navCtx.mounted) return;
        _startupUpdateDialogShown = true;
        unawaited(UpdateDialog.show(navCtx, info));
      });
    };
    router.routerDelegate.addListener(listener);
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Cap the framework's decoded-image cache so artwork bitmaps cannot balloon
  // RAM under heavy scrolling (80 MB / 250 image ceiling).
  PaintingBinding.instance.imageCache.maximumSizeBytes = 80 << 20;
  PaintingBinding.instance.imageCache.maximumSize = 250;
  HttpOverrides.global = AppHttpOverrides.instance;
  // A production build with dev flags cannot be patched at runtime: surface a
  // blocking configuration screen instead of logging and continuing with
  // illegal flags (Play Store compliance).
  Object? fatalConfigError;
  try {
    AppConfig.validateConfiguration();
  } catch (e, st) {
    fatalConfigError = e;
    ErrorLogger.log('AppConfig.validateConfiguration error',
        error: e, stackTrace: st, category: 'Startup');
  }

  ErrorLogger.onCrashReported = (error, stackTrace, category) {
    // Single-sink rule: the Sentry capture (with scope tags) is owned by
    // ErrorLogger.log. This hook only mirrors the report to logcat so the
    // crash is not reported twice.
    debugPrint('[Pulsr.CrashReport][$category] $error\n$stackTrace');
  };
  ErrorLogger.initialize();
  Bloc.observer = PulsrBlocObserver.instance;

  // FIX-A3: Global error boundary for widget build errors
  ErrorWidget.builder = (FlutterErrorDetails details) {
    ErrorLogger.log(
      'Widget build error',
      error: details.exception,
      stackTrace: details.stack,
      category: 'UI',
    );
    return Builder(
      builder: (context) => Material(
        // Theme may not be reachable when a build error happens high in the
        // tree; a fixed dark surface keeps the fallback readable in both modes.
        color: AppColors.card,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 40,
                  color: Colors.white54,
                ),
                const SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context)?.somethingWentWrong ??
                      'Something went wrong',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  };

  if (fatalConfigError != null) {
    runApp(PulsrConfigurationErrorApp(
      title: AppConfig.appTitle,
      message: fatalConfigError.toString(),
    ));
    return;
  }

  // Resolve the installed version before any screen (Settings/About, updater)
  // reads AppConfig.appVersion. Best-effort: the 2.0.0 fallback is only used
  // when the platform channel is unavailable.
  await AppConfig.loadInstalledVersion()
      .timeout(const Duration(seconds: 2), onTimeout: () {});

  // Initialize in-memory SettingsCache synchronously enough for the first
  // frame. Artwork and UI-sound init are not needed to paint the shell, so they
  // run behind the first frame instead of adding path_provider/prefs awaits to
  // the cold-start critical path.
  try {
    await SettingsCache().init();
  } catch (_) {}
  unawaited(ArtworkCacheManager().init().catchError((e, st) {
    ErrorLogger.log('ArtworkCacheManager init failed',
        error: e, stackTrace: st, category: 'Startup');
  }));
  unawaited(SoundFeedbackService.init());

  // Rehydrate the GPU budget before first frame (persisted by SettingsCubit).
  try {
    final prefs = await SharedPreferences.getInstance();
    try {
      await EqLegacyMigration.run(prefs);
    } catch (e, st) {
      ErrorLogger.log('EQ legacy migration failed',
          error: e, stackTrace: st, category: 'Startup');
    }
    GpuBudget.setEnabled(prefs.getBool('setting_reduce_motion') ?? false);
    PulsrHaptics.setEnabled(prefs.getBool(PrefsKeys.hapticsEnabled) ?? true);
  } catch (_) {}
  // Warm native audio capability cache (best-effort, never blocks).
  unawaited(PlatformCapabilities.ensureLoaded()
      .timeout(const Duration(seconds: 5))
      .catchError((_) {}));
  // Pre-warm GPU visualizer shader in background (never blocks cold start).
  unawaited(AudioVisualizer.prewarmShader());

  // Firebase powers Auth + (optionally) cloud sync. Pure builds must perform
  // zero network work, so skip init there; elsewhere init best-effort so a
  // missing google-services file never blocks startup.
  if (!AppConfig.isPure) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 3));
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
    await configureDependencies(warmUpAsync: false)
        .timeout(const Duration(seconds: 15));
  } catch (e, st) {
    ErrorLogger.log('DI configureDependencies failed or timed out',
        error: e, stackTrace: st, category: 'Startup');
  }

  SoundFeedbackService.isMusicPlaying = () {
    try {
      if (_isDependencyReady<PulsrAudioHandler>()) {
        return getIt<PulsrAudioHandler>().playbackState.value.playing;
      }
    } catch (_) {}
    return false;
  };

  // Defer heavy post-DI tasks to AFTER runApp to eliminate Davey! 1223ms jank on OnePlus
  // Previously awaited 3x8s before first frame -> Skipped 121 frames. Now fire-and-forget.
  void firePostStartupTasks() {
    // Run after first frame renders on screen so startup paints without jank
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Respect the user's offline-only setting at cold start: it must disable
      // every online initializer, not just the UI surfaces (mirrors
      // CloudSyncService's runtime gate). SharedPreferences MUST be awaited
      // before computing the gates; resolving it in a later microtask let the
      // synchronous onlineAllowed computation ignore offline-only mode.
      SharedPreferences? prefs;
      try {
        prefs = await SharedPreferences.getInstance();
      } catch (e, st) {
        ErrorLogger.log('Failed to read startup preferences',
            error: e, stackTrace: st, category: 'Startup');
      }
      final onlineAllowed = StartupGates.onlineAllowed(prefs);
      final cloudSyncAllowed = StartupGates.cloudSyncAllowed(prefs);
      try {
        Future.wait([
          // Pure builds have no INTERNET permission: skip every online
          // initializer so Pulsr Pure performs zero network work at startup.
          if (onlineAllowed)
            YtmRateLimiter.shared
                .restore()
                .timeout(const Duration(seconds: 4))
                .catchError((e, st) {
              ErrorLogger.log('YtmRateLimiter restore failed or timed out',
                  error: e, stackTrace: st, category: 'Startup');
            }),
          if (cloudSyncAllowed)
            getIt<AuthService>()
                .initialize()
                .timeout(const Duration(seconds: 4))
                .catchError((e, st) {
              ErrorLogger.log('AuthService initialize failed or timed out',
                  error: e, stackTrace: st, category: 'Startup');
            }),
          if (onlineAllowed)
            getIt<YtmAccountService>()
                .init()
                // init() reads the WebView cookie jar over a platform channel
                // and the secure-storage keystore, both of which can take
                // several seconds on a cold/emulated device. The 8 s budget
                // fired there and reported a healthy boot as a crash.
                .timeout(const Duration(seconds: 20))
                .catchError((e, st) {
              ErrorLogger.log('YtmAccountService init failed or timed out',
                  error: e, stackTrace: st, category: 'Startup');
            }),
          if (onlineAllowed && getIt.isRegistered<YtmClientVersionResolver>())
            getIt<YtmClientVersionResolver>()
                .init()
                .timeout(const Duration(seconds: 8))
                .catchError((e, st) {
              ErrorLogger.log(
                  'YtmClientVersionResolver init failed or timed out',
                  error: e,
                  stackTrace: st,
                  category: 'Startup');
            }),
          // Rehydrate guest stream URLs saved by the previous run so a replay
          // or skip-back after launch resolves instantly.
          if (onlineAllowed && getIt.isRegistered<YtmUrlCache>())
            getIt<YtmUrlCache>()
                .restore()
                .timeout(const Duration(seconds: 8))
                .catchError((e, st) {
              ErrorLogger.log('YtmUrlCache restore failed or timed out',
                  error: e, stackTrace: st, category: 'Startup');
            }),
        ]);
        // Optional remote override for the native client matrix. The channel could
        // always apply one, but nothing in the app ever pushed JSON to it, so a client
        // version or capability change needed a release. Opt-in: empty unless the build
        // defines YTM_CAPABILITIES_URL, which keeps the packaged asset authoritative
        // everywhere else. Fire-and-forget and failure-tolerant.
        try {
          const capabilitiesUrl =
              String.fromEnvironment('YTM_CAPABILITIES_URL');
          if (onlineAllowed &&
              capabilitiesUrl.isNotEmpty &&
              getIt.isRegistered<YtmService>()) {
            unawaited(getIt<YtmService>()
                .refreshClientCapabilitiesFrom(capabilitiesUrl)
                .timeout(const Duration(seconds: 12))
                .catchError((_) => false));
          }
        } catch (_) {}
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
          if (cloudSyncAllowed && getIt.isRegistered<ScrobblerService>()) {
            final scrobbler = getIt<ScrobblerService>();
            unawaited(scrobbler
                .migrateAllCredentialsToSecureStorage()
                .then((_) => scrobbler.checkPendingScrobble())
                // Secure-storage keystore access is the slow part on a cold
                // boot (seconds on an emulator's first decrypt); 10 s cut it
                // off mid-migration and reported a false crash.
                .timeout(const Duration(seconds: 30))
                .catchError((e, st) {
              ErrorLogger.log('Scrobbler startup recovery failed',
                  error: e, stackTrace: st, category: 'Startup');
            }));
          }
        } catch (e, st) {
          ErrorLogger.log('Scrobbler startup hook failed',
              error: e, stackTrace: st, category: 'Startup');
        }

        // Initialize Discord RPC if configured and online allowed
        try {
          if (onlineAllowed && prefs != null) {
            unawaited(DiscordRpcService.instance.init(prefs).then((_) async {
              // PlayerCubit is an async singleton; wait for readiness instead
              // of calling getIt<T>() while the DI warm-up is still pending.
              final player = await _resolveDependency<PlayerCubit>()
                  .timeout(const Duration(seconds: 30));
              DiscordRpcService.instance.bindToPlayerCubit(player);
            }).catchError((e, st) {
              ErrorLogger.log('DiscordRpcService init failed',
                  error: e, stackTrace: st, category: 'Startup');
            }));
          }
        } catch (e, st) {
          ErrorLogger.log('DiscordRpcService startup hook failed',
              error: e, stackTrace: st, category: 'Startup');
        }

        // Initialize Listen Together party auto-rejoin once PlayerCubit is ready
        try {
          if (onlineAllowed && getIt.isRegistered<ListenTogetherService>()) {
            unawaited(_resolveDependency<PlayerCubit>()
                .timeout(const Duration(seconds: 30))
                .then((_) => getIt<ListenTogetherService>()
                    .init()
                    .timeout(const Duration(seconds: 10)))
                .catchError((e, st) {
              ErrorLogger.log('ListenTogetherService init failed',
                  error: e, stackTrace: st, category: 'Startup');
            }));
          }
        } catch (e, st) {
          ErrorLogger.log('ListenTogetherService startup hook failed',
              error: e, stackTrace: st, category: 'Startup');
        }

        // Best-effort check for app updates off GitHub releases
        try {
          if (onlineAllowed) {
            unawaited(AppUpdateService.instance.check().then((info) {
              if (info != null) {
                _surfaceStartupUpdate(info);
              }
            }).catchError((e, st) {
              ErrorLogger.log('AppUpdateService startup check failed',
                  error: e, stackTrace: st, category: 'Startup');
            }));
          }
        } catch (e, st) {
          ErrorLogger.log('AppUpdateService startup hook failed',
              error: e, stackTrace: st, category: 'Startup');
        }
      } catch (e, st) {
        ErrorLogger.log('Parallel startup init failed',
            error: e, stackTrace: st, category: 'Startup');
      }
    });
  }

  var appStarted = false;
  if (AppConfig.isTelemetryAllowed) {
    try {
      await SentryFlutter.init(
        (options) {
          options.dsn = AppConfig.sentryDsn;
          options.environment = AppConfig.envName;
          options.tracesSampleRate = AppConfig.isProd ? 0.2 : 1.0;
          options.sendDefaultPii = false;
          options.enableAutoPerformanceTracing = true;
          options.beforeSend = (event, hint) {
            final msg = event.message;
            final scrubbedMessage = msg != null
                ? SentryMessage(
                    ErrorLogger.redactPii(msg.formatted),
                    template: msg.template != null
                        ? ErrorLogger.redactPii(msg.template!)
                        : null,
                    params: msg.params
                        ?.map((p) => p is String ? ErrorLogger.redactPii(p) : p)
                        .toList(),
                  )
                : null;
            // Exception values (HTTP/URL/session errors) bypass the message
            // field, so scrub them too before the event leaves the device.
            final scrubbedExceptions = event.exceptions
                ?.map((e) => e.value == null
                    ? e
                    : e.copyWith(value: ErrorLogger.redactPii(e.value!)))
                .toList();
            return event.copyWith(
              user: null,
              message: scrubbedMessage,
              exceptions: scrubbedExceptions,
            );
          };
        },
        appRunner: () {
          appStarted = true;
          runApp(const PulsrApp());
          firePostStartupTasks();
        },
      );
    } catch (e, st) {
      // A telemetry init failure must never black-screen the app: fall through
      // to the un-instrumented startup path below.
      ErrorLogger.log('SentryFlutter.init failed — starting without telemetry',
          error: e, stackTrace: st, category: 'Startup');
    }
  }
  if (!appStarted) {
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
  GoRouter? _router;
  StreamSubscription<void>? _authExpiredSub;
  StreamSubscription<void>? _networkChangeSub;
  NetworkChangeMonitor? _networkMonitor;
  AutomationTriggerService? _automationTriggerService;
  AnnouncementSettings? _announcementSettings;
  TtsEngine? _ttsEngine;
  TrackAnnouncer? _trackAnnouncer;
  AssistantSettings? _assistantSettings;
  SystemBehaviorSettings? _systemBehaviorSettings;
  VoidCallback? _systemBehaviorSettingsListener;
  SystemBehaviorRuntime? _systemBehaviorRuntime;
  AudioProfileBootstrap? _audioProfileBootstrap;
  UsbErgonomicsService? _usbErgonomics;
  RemotePlaybackRuntime? _remotePlaybackRuntime;
  DlnaRendererService? _dlnaRendererService;
  VoidCallback? _platformBridgeDegradedListener;
  DateTime? _lastAuthExpiredPrompt;
  bool _dependenciesReady = false;
  bool _bootstrapFailed = false;
  bool _bootstrapInFlight = false;
  bool _pausedSinceStart = false;
  bool _resumeScanInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _router = _createRouterSafely();
    _dependenciesReady = appDependenciesReady;
    if (!_dependenciesReady) {
      unawaited(_resolveDependencies());
    }
    _autoScanOnStartup();
    _checkInitialAudioIntent();
    if (AppConfig.ytmEnabled) _listenForYtmSessionExpiry();
    if (AppConfig.isCloudSyncAllowed) _startNetworkChangeMonitor();
    _startAutomationTriggers();
    _startTrackAnnouncements();
    _startAssistantSuggestions();
    _startSystemAndUsbServices();
    _startAudioProfileScheduler();
    _registerRemotePlaybackRuntime();
    _watchPlatformBridgeHealth();
    _verifyPureMode();
  }

  GoRouter? _createRouterSafely() {
    try {
      return createRouter(getIt<MediaScannerService>());
    } catch (e, st) {
      ErrorLogger.log('Router creation failed — bootstrap will retry',
          error: e, stackTrace: st, category: 'Startup');
      return null;
    }
  }

  /// Awaits the async singletons the UI resolves synchronously. A slow or
  /// partially failed warm-up paints a retry screen instead of crashing in
  /// build with an un-ready StateError.
  Future<void> _resolveDependencies({bool reconfigureIfNeeded = false}) async {
    if (_bootstrapInFlight) return;
    _bootstrapInFlight = true;
    final ready = await ensureAppDependenciesReady(
      reconfigureIfNeeded: reconfigureIfNeeded,
    );
    _bootstrapInFlight = false;
    if (!mounted) return;
    if (ready) {
      // The router can only be built once MediaScannerService is resolvable.
      // With the deferred warm-up this is the first point where that is true.
      _router ??= _createRouterSafely();
    }
    final resolvedReady = ready && _router != null;
    setState(() {
      _dependenciesReady = resolvedReady;
      _bootstrapFailed = !resolvedReady;
    });
  }

  void _retryBootstrap() {
    if (!mounted) return;
    setState(() {
      _bootstrapFailed = false;
    });
    if (!_dependenciesReady || _router == null) {
      unawaited(_resolveDependencies(reconfigureIfNeeded: true));
    }
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
              message: ctx.l10n.pureIntegrityCheckFailed,
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
    // PulsrAudioHandler is an async singleton: isRegistered() is already true
    // while the instance is still pending, so wait for readiness instead of
    // calling getIt<T>() and throwing "not ready yet".
    unawaited(() async {
      try {
        final handler = await _resolveDependency<PulsrAudioHandler>()
            .timeout(const Duration(seconds: 30));
        if (!mounted) return;
        void surface() {
          if (!handler.platformBridgeDegraded.value) return;
          final ctx = rootNavigatorKey.currentContext;
          if (ctx == null || !ctx.mounted) return;
          PulsrToast.show(
            ctx,
            message: ctx.l10n.backgroundMediaControlsUnavailable,
            icon: Icons.warning_amber_rounded,
            isError: true,
            duration: const Duration(seconds: 5),
          );
        }

        if (handler.platformBridgeDegraded.value) {
          WidgetsBinding.instance.addPostFrameCallback((_) => surface());
        } else if (_platformBridgeDegradedListener == null) {
          handler.platformBridgeDegraded.addListener(surface);
          _platformBridgeDegradedListener = surface;
        }
      } catch (e, st) {
        // Best-effort diagnostic only; never let it block startup (e.g. a test
        // double of the handler that does not expose the notifier).
        ErrorLogger.log('Failed to watch platform bridge health',
            error: e, stackTrace: st, category: 'Startup');
      }
    }());
  }

  /// Watches output-device changes (Bluetooth/headphones) and fires the
  /// matching user automation rules. Charging is intentionally not wired: it
  /// is not reliably observable from Dart without a native change.
  void _startAutomationTriggers() {
    try {
      final service = getIt.isRegistered<AutomationTriggerService>()
          ? getIt<AutomationTriggerService>()
          : AutomationTriggerService();
      _automationTriggerService = service;
      service.start();
    } catch (e, st) {
      ErrorLogger.log('Failed to start automation trigger service',
          error: e, stackTrace: st, category: 'Startup');
    }
  }

  /// Applies the profile the user marked as the audio-profile default.
  ///
  /// Runs once after the startup settings are readable, then again whenever a
  /// USB DAC is attached and the profile pins a matching vid/pid. The service
  /// keeps a last-applied marker, so settings refreshes and duplicate device
  /// events cannot loop. Nothing here may abort startup: failures are logged.
  void _startAudioProfileScheduler() {
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final service = AudioProfileService(prefs: prefs);
        final bootstrap = AudioProfileBootstrap(service: service);
        if (!mounted) {
          bootstrap.dispose();
          return;
        }
        _audioProfileBootstrap = bootstrap;
        await bootstrap.start();
      } catch (e, st) {
        ErrorLogger.log(
          'Audio-profile scheduler failed to start',
          error: e,
          stackTrace: st,
          category: 'AudioProfiles',
        );
      }
    }());
  }

  /// System-behaviour policies (P1-7), USB DAC quirks (P0-3) and the live
  /// playback adapter they act through.
  ///
  /// [SystemBehaviorRuntime] owns the audio-session subscriptions, the native
  /// task-removal mirror and USB release/reclaim on background transitions.
  /// The notification policy is still routed through [SettingsCubit] so the
  /// in-memory state, persisted preference and audio handler stay in sync.
  void _startSystemAndUsbServices() {
    unawaited(() async {
      try {
        final behaviorSettings = SystemBehaviorSettings();
        await behaviorSettings.load();
        final prefs = await SharedPreferences.getInstance();
        final usbErgonomics = UsbErgonomicsService(
          store: UsbQuirkStore(prefs: prefs),
        );
        await usbErgonomics.start();
        final handler = await _resolveDependency<PulsrAudioHandler>()
            .timeout(const Duration(seconds: 30));
        if (!mounted) {
          behaviorSettings.dispose();
          usbErgonomics.dispose();
          return;
        }
        final runtime = await SystemBehaviorRuntime.start(
          settings: behaviorSettings,
          handler: handler,
          readVolume: () => handler.volume,
          writeVolume: handler.setVolume,
        );
        if (!mounted) {
          runtime.dispose();
          behaviorSettings.dispose();
          usbErgonomics.dispose();
          return;
        }
        if (!getIt.isRegistered<SystemBehaviorSettings>()) {
          getIt.registerSingleton<SystemBehaviorSettings>(behaviorSettings);
        }
        if (!getIt.isRegistered<UsbErgonomicsService>()) {
          getIt.registerSingleton<UsbErgonomicsService>(usbErgonomics);
        }
        _systemBehaviorSettings = behaviorSettings;
        _systemBehaviorRuntime = runtime;
        _usbErgonomics = usbErgonomics;
        _systemBehaviorSettingsListener = () => unawaited(
              _applySystemBehaviorGlue(behaviorSettings),
            );
        behaviorSettings.addListener(_systemBehaviorSettingsListener!);
        await _applySystemBehaviorGlue(behaviorSettings);
      } catch (e, st) {
        ErrorLogger.log(
          'System behaviour / USB ergonomics failed to start',
          error: e,
          stackTrace: st,
          category: 'Startup',
        );
      }
    }());
  }

  /// Owns the network-library stream server for the process lifetime, so a
  /// playing remote track keeps its URL after the Extras screen is popped.
  void _registerRemotePlaybackRuntime() {
    if (!getIt.isRegistered<RemotePlaybackRuntime>()) {
      final runtime = RemotePlaybackRuntime();
      getIt.registerSingleton<RemotePlaybackRuntime>(runtime);
      _remotePlaybackRuntime = runtime;
    }
    if (!getIt.isRegistered<DlnaRendererService>()) {
      final dlna = DlnaRendererService();
      getIt.registerSingleton<DlnaRendererService>(dlna);
      _dlnaRendererService = dlna;
    }
  }

  /// Mirrors the notification policy into [SettingsCubit], whose state is what
  /// the audio handler reads. `SystemBehaviorSettings` delegates the same pref,
  /// so this is idempotent and never overwrites an independent setting.
  Future<void> _applySystemBehaviorGlue(SystemBehaviorSettings settings) async {
    try {
      if (getIt.isRegistered<SettingsCubit>()) {
        final desired = settings.pauseOnNotificationSound ? 'pause' : 'duck';
        final cubit = getIt<SettingsCubit>();
        if (cubit.state.duckingMode != desired) {
          await cubit.setDuckingMode(desired);
        }
        if (cubit.state.resumeAfterInterruption != settings.resumeAfterCall) {
          await cubit.setResumeAfterInterruption(settings.resumeAfterCall);
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to sync notification policy',
          error: e, stackTrace: st, category: 'SystemBehavior');
    }
  }

  /// Keeps the Android search-suggestion cache warm (P1-9). Local-only and
  /// failure-tolerant: without the platform channel this is a no-op.
  void _startAssistantSuggestions() {
    // Install the assistant channel as early as the container allows: a
    // MEDIA_PLAY_FROM_SEARCH intent that launches the app must not wait for the
    // full async warm-up before it can be resolved.
    AssistantIntentBootstrap.ensureInstalled();
    unawaited(() async {
      try {
        await getIt.allReady().timeout(const Duration(seconds: 30));
        if (!mounted) return;
        AssistantIntentBootstrap.ensureInstalled();
        if (!getIt.isRegistered<IMusicRepository>()) return;
        // One settings instance for the process: the Extras toggle writes it
        // and this sync reads it, so flipping the opt-in takes effect without
        // a restart.
        final hadSettings = getIt.isRegistered<AssistantSettings>();
        final settings = hadSettings
            ? getIt<AssistantSettings>()
            : await AssistantSettings.load();
        if (!mounted) {
          if (!hadSettings) settings.dispose();
          return;
        }
        if (!getIt.isRegistered<AssistantSettings>()) {
          getIt.registerSingleton<AssistantSettings>(settings);
        }
        _assistantSettings = settings;
        await AssistantSuggestionSync(
          repository: getIt<IMusicRepository>(),
          settings: settings,
        ).pushRecent().timeout(const Duration(seconds: 10));
      } catch (e, st) {
        ErrorLogger.log(
          'Search suggestion sync skipped',
          error: e,
          stackTrace: st,
          category: 'Startup',
        );
      }
    }());
  }

  /// Spoken track announcements (P0-4). Started once the audio handler exists so
  /// the announcer can follow its media-item stream. Ownership lives here: the
  /// announcer, its settings and the TTS engine are disposed with the app.
  void _startTrackAnnouncements() {
    unawaited(() async {
      try {
        final handler = await _resolveDependency<PulsrAudioHandler>()
            .timeout(const Duration(seconds: 30));
        if (!mounted) return;
        // One settings/engine pair for the whole process. The Extras hub edits
        // these same instances, so toggles and voice changes reach the live
        // announcer without a restart.
        final hadSettings = getIt.isRegistered<AnnouncementSettings>();
        final settings = hadSettings
            ? getIt<AnnouncementSettings>()
            : await AnnouncementSettings.load();
        if (!mounted) {
          if (!hadSettings) settings.dispose();
          return;
        }
        final hadEngine = getIt.isRegistered<MethodChannelTtsEngine>();
        final engine = hadEngine
            ? getIt<MethodChannelTtsEngine>()
            : MethodChannelTtsEngine();
        await engine.init();
        if (!mounted) {
          if (!hadSettings) settings.dispose();
          if (!hadEngine) unawaited(engine.dispose());
          return;
        }
        engine.voiceId = settings.voiceId;
        engine.localeId = settings.localeId;
        if (!getIt.isRegistered<AnnouncementSettings>()) {
          getIt.registerSingleton<AnnouncementSettings>(settings);
        }
        if (!getIt.isRegistered<MethodChannelTtsEngine>()) {
          getIt.registerSingleton<MethodChannelTtsEngine>(engine);
        }
        final announcer = TrackAnnouncer(
          mediaItemStream: handler.mediaItem,
          playbackStateStream: handler.playbackState,
          settings: settings,
          engine: engine,
          shouldSkip: () => CastService().sessionStatus.connected,
          isBitPerfect: () =>
              SettingsCache().getBool(PrefsKeys.strictBitPerfect) ||
              SettingsCache().getBool(PrefsKeys.bitPerfectOutput),
        )..start();
        _announcementSettings = settings;
        _ttsEngine = engine;
        _trackAnnouncer = announcer;
      } catch (e, st) {
        ErrorLogger.log(
          'Track announcements failed to start',
          error: e,
          stackTrace: st,
          category: 'Startup',
        );
      }
    }());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // No-op for locale; pick up media-store changes after a real background
      // stint using the scanner's 15-minute delta gate.
      if (_pausedSinceStart) {
        unawaited(_maybeRescanOnResume());
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _pausedSinceStart = true;
      // USB release/reclaim is owned by SystemBehaviorRuntime, which checks
      // whether playback is active before dropping the exclusive claim.
      // Flush the debounced queue-slot write before the process can be killed.
      try {
        if (_isDependencyReady<PlayerCubit>()) {
          unawaited(getIt<PlayerCubit>().persistQueueSlotsNow());
        }
      } catch (e, st) {
        ErrorLogger.log('Failed to persist queue slots on detach',
            error: e, stackTrace: st, category: 'PulsrApp');
      }
    }
  }

  /// Runs a silent, time-gated delta scan so tracks added while the app was
  /// backgrounded appear without the user manually opening Settings.
  Future<void> _maybeRescanOnResume() async {
    // MediaStore/photo permissions only exist on mobile; desktop scans on an
    // explicit request. Skipping keeps widget tests and desktop startup quiet.
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_resumeScanInFlight) return;
    _resumeScanInFlight = true;
    try {
      final scanner = getIt<MediaScannerService>();
      if (!scanner.shouldRescanOnResume()) return;
      if (!await scanner.checkPermission()) return;
      if (!mounted) return;
      final settings = getIt<SettingsCubit>().state;
      final prefs = await SharedPreferences.getInstance();
      await scanner.scanDeviceLibrary(
        ignoreShortFiles: settings.minDurationSec > 0,
        minDurationSec: settings.minDurationSec,
        minSizeKb: prefs.getInt('setting_min_file_size_kb') ?? 0,
        autoHideSystemMedia: settings.autoHideSystemMedia,
        incremental: true,
      );
    } catch (e, st) {
      ErrorLogger.log('Resume media scan failed',
          error: e, stackTrace: st, category: 'PulsrApp');
    } finally {
      _resumeScanInFlight = false;
    }
  }

  @override
  void didHaveMemoryPressure() {
    // Trim artwork and stream caches on GC pressure (LOG-14 14MB/59MB).
    // Clear only the in-memory bytes; the persistent disk cache is kept so a
    // transient memory warning does not force a full re-fetch + re-decode.
    try {
      final cacheManager = getIt.isRegistered<ArtworkCacheManager>()
          ? getIt<ArtworkCacheManager>()
          : ArtworkCacheManager();
      cacheManager.trimMemoryForPressure();
    } catch (e, st) {
      ErrorLogger.log('Failed to trim artwork memory cache on memory pressure',
          error: e, stackTrace: st, category: 'PulsrApp');
    }
    try {
      ArtworkLruCache().trimForMemoryPressure();
    } catch (e, st) {
      ErrorLogger.log('Failed to trim artwork LRU cache on memory pressure',
          error: e, stackTrace: st, category: 'PulsrApp');
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
          ScaffoldMessenger.maybeOf(ctx)
            ?..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(ctx.l10n.ytmSessionExpired),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 6),
                action: SnackBarAction(
                  label: ctx.l10n.signIn,
                  onPressed: () => YtmWebLoginSheet.show(ctx),
                ),
              ),
            );
        });
      } catch (e, st) {
        ErrorLogger.log('Failed to listen for Ytm session expiry',
            error: e, stackTrace: st, category: 'PulsrApp');
      }
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
          ErrorLogger.log('Network path changed — invalidating YTM caches',
              category: 'PulsrApp');
          try {
            if (getIt.isRegistered<YtmService>()) {
              await getIt<YtmService>().handleNetworkChange();
            }
          } catch (e, st) {
            ErrorLogger.log('Failed handling network change in YtmService',
                error: e, stackTrace: st, category: 'PulsrApp');
          }
          try {
            if (_isDependencyReady<PulsrAudioHandler>()) {
              getIt<PulsrAudioHandler>().clearNetworkCaches();
            }
          } catch (e, st) {
            ErrorLogger.log('Failed clearing audio handler network caches',
                error: e, stackTrace: st, category: 'PulsrApp');
          }
          try {
            if (getIt.isRegistered<IDownloadRepository>()) {
              final resumed =
                  await getIt<IDownloadRepository>().resumeAutoPaused();
              if (resumed > 0) {
                ErrorLogger.log(
                    'Network restored — resumed $resumed auto-paused downloads',
                    category: 'PulsrApp');
              }
            }
          } catch (e, st) {
            ErrorLogger.log('Failed resuming policy-paused downloads',
                error: e, stackTrace: st, category: 'PulsrApp');
          }
        });
      } catch (e, st) {
        ErrorLogger.log('Failed to start network change monitor',
            error: e, stackTrace: st, category: 'PulsrApp');
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authExpiredSub?.cancel();
    _networkChangeSub?.cancel();
    _networkMonitor?.dispose();
    _automationTriggerService?.dispose();
    unawaited(_trackAnnouncer?.dispose() ?? Future<void>.value());
    unawaited(_ttsEngine?.dispose() ?? Future<void>.value());
    _announcementSettings?.dispose();
    AssistantIntentBootstrap.dispose();
    _assistantSettings?.dispose();
    if (_systemBehaviorSettingsListener != null) {
      _systemBehaviorSettings?.removeListener(_systemBehaviorSettingsListener!);
    }
    _systemBehaviorRuntime?.dispose();
    _audioProfileBootstrap?.dispose();
    _systemBehaviorSettings?.dispose();
    _usbErgonomics?.dispose();
    unawaited(
      _remotePlaybackRuntime?.dispose() ?? Future<void>.value(),
    );
    _dlnaRendererService?.dispose();
    if (_platformBridgeDegradedListener != null &&
        _isDependencyReady<PulsrAudioHandler>()) {
      getIt<PulsrAudioHandler>()
          .platformBridgeDegraded
          .removeListener(_platformBridgeDegradedListener!);
    }
    // The audio-output services are process singletons constructed at call
    // sites rather than through DI; without this their event subscriptions and
    // broadcast controllers would live until process exit.
    try {
      UsbExclusiveService().dispose();
      if (getIt.isRegistered<HiResAudioService>()) {
        getIt<HiResAudioService>().dispose();
      }
      CastService().dispose();
    } catch (e, st) {
      ErrorLogger.log('Failed to dispose audio output singletons',
          error: e, stackTrace: st, category: 'PulsrApp');
    }
    super.dispose();
  }

  void _checkInitialAudioIntent() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final handler = await getIt.getAsync<FileIntentHandler>();
        if (!mounted) return;
        await handler.checkInitialUri();
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
    final router = _router;
    if (!_dependenciesReady || router == null) {
      return _DependencyBootstrapScreen(
        failed: _bootstrapFailed || (router == null && _dependenciesReady),
        onRetry: _retryBootstrap,
      );
    }
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
                      message: resolveUiErrorMessage(overlayCtx, message),
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
                VisualDensityMode visualDensityMode,
                Color customAccent,
                String languageCode,
                bool highContrast,
                bool reduceMotion,
                bool dimWhitePoint,
                AppButtonStyle appButtonStyle
              })>(
            selector: (state) => (
              colorSource: state.themeColorSource,
              themeMode: state.themeMode,
              visualDensityMode: state.visualDensityMode,
              customAccent: state.customAccentColor,
              languageCode: state.languageCode,
              highContrast: state.highContrast,
              reduceMotion: state.reduceMotion,
              dimWhitePoint: state.dimWhitePoint,
              appButtonStyle: state.appButtonStyle,
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
                      final isCalmDensity = settingsConfig.visualDensityMode ==
                          VisualDensityMode.calm;
                      final buttonRadius = PulsrCapsuleStyle.resolveRadius(
                        settingsConfig.appButtonStyle,
                        rectRadius: AppRadii.r14,
                      );

                      final lightTheme = isHighContrast
                          ? AuraTheme.highContrastThemeFor(Brightness.light,
                              seed: resolveAccent(lightDynamic?.primary),
                              isCalmDensity: isCalmDensity,
                              buttonRadius: buttonRadius)
                          : AuraTheme.customTheme(
                              resolveAccent(lightDynamic?.primary),
                              brightness: Brightness.light,
                              isBoldText: isBoldText,
                              isCalmDensity: isCalmDensity,
                              buttonRadius: buttonRadius,
                            );

                      final darkTheme = isHighContrast
                          ? AuraTheme.highContrastThemeFor(Brightness.dark,
                              seed: resolveAccent(darkDynamic?.primary),
                              isCalmDensity: isCalmDensity,
                              buttonRadius: buttonRadius)
                          : AuraTheme.customTheme(
                              resolveAccent(darkDynamic?.primary),
                              brightness: Brightness.dark,
                              isAmoled: settingsConfig.themeMode ==
                                  AppThemeMode.amoled,
                              isBoldText: isBoldText,
                              dimWhitePoint: settingsConfig.dimWhitePoint,
                              isCalmDensity: isCalmDensity,
                              buttonRadius: buttonRadius,
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

                      final isDarkTheme = switch (settingsConfig.themeMode) {
                        AppThemeMode.light => false,
                        AppThemeMode.dark || AppThemeMode.amoled => true,
                        AppThemeMode.system =>
                          MediaQuery.platformBrightnessOf(context) ==
                              Brightness.dark,
                      };

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
                          restorationScopeId: 'pulsr',
                          themeMode: flutterThemeMode,
                          theme: lightTheme,
                          darkTheme: darkTheme,
                          builder: (context, child) {
                            // Expose the active localizations to non-widget code
                            // (cubits/services) via L10nHolder.
                            L10nHolder.current = AppLocalizations.of(context);
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
                                // The app ships its own High Contrast mode as a
                                // theme. Mirror it into MediaQuery so every
                                // accessibility consumer (notably
                                // AppBlur.canBlur) sees one signal instead of
                                // two, and the solid-surface fallback actually
                                // fires for the in-app toggle.
                                highContrast: settingsConfig.highContrast ||
                                    media.highContrast,
                              ),
                              child: MediaQuery.withClampedTextScaling(
                                // Accessibility: allow the full OS text-size
                                // range (up to 200%). Fixed-height text boxes
                                // on key surfaces scale via
                                // MediaQuery.textScalerOf so nothing clips.
                                minScaleFactor: 0.8,
                                maxScaleFactor: 2.0,
                                child: _AppOrientationSystemUiObserver(
                                  child: HeroMode(
                                    // A shared-element flight is the largest
                                    // movement in the product; it must obey the
                                    // same Reduce Motion contract as every
                                    // token-driven animation.
                                    enabled: !reduceMotion,
                                    child: child ?? const SizedBox.shrink(),
                                  ),
                                ),
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
                          routerConfig: router,
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

/// Global system UI observer mounted in [MaterialApp.builder] to ensure all
/// screens across the entire application remain in immersive full-screen mode
/// in landscape orientation (hiding status and navigation letterbox bars),
/// and gracefully return to edge-to-edge with transparent system bars in portrait.
class _AppOrientationSystemUiObserver extends StatefulWidget {
  final Widget child;
  const _AppOrientationSystemUiObserver({required this.child});

  @override
  State<_AppOrientationSystemUiObserver> createState() =>
      _AppOrientationSystemUiObserverState();
}

class _AppOrientationSystemUiObserverState
    extends State<_AppOrientationSystemUiObserver> with WidgetsBindingObserver {
  Orientation? _lastOrientation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.orientationOf(context);
    if (orientation != _lastOrientation) {
      _lastOrientation = orientation;
      _applySystemUi(orientation);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _lastOrientation != null) {
      _applySystemUi(_lastOrientation!);
    }
  }

  void _applySystemUi(Orientation orientation) {
    if (orientation == Orientation.landscape) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
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
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Blocking screen shown when the build's flavor/environment configuration is
/// invalid (e.g. a Play Store build shipping YTM flags). The app must not
/// start with an illegal configuration, so this is terminal — not recoverable.
class PulsrConfigurationErrorApp extends StatelessWidget {
  final String title;
  final String message;

  const PulsrConfigurationErrorApp({
    super.key,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      theme: AuraTheme.darkTheme,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (innerContext) => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 52, color: Colors.redAccent),
                  const SizedBox(height: 18),
                  Text(
                    innerContext.l10n.bootConfigurationError,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: AppFontSize.title, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(fontSize: AppFontSize.body, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Recoverable boot/retry screen rendered while the async DI singletons the
/// shell needs are still warming up (or after a warm-up failure). Prevents the
/// un-ready-StateError crash that previously black-screened slow cold starts.
class _DependencyBootstrapScreen extends StatelessWidget {
  final bool failed;
  final VoidCallback onRetry;

  const _DependencyBootstrapScreen({
    required this.failed,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AuraTheme.darkTheme,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (innerContext) => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!failed)
                    const CircularProgressIndicator()
                  else ...[
                    const Icon(Icons.refresh_rounded,
                        size: 48, color: Colors.white70),
                    const SizedBox(height: 16),
                    Text(
                      innerContext.l10n.bootStartupFailed,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: AppFontSize.subtitle,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      innerContext.l10n.bootStartupFailedMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: AppFontSize.bodySmall, height: 1.4),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: onRetry,
                      child: Text(innerContext.l10n.retry),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
