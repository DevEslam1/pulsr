import 'dart:async';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

import 'package:pulsr/core/config/app_config.dart';
import 'package:pulsr/core/services/file_intent_handler.dart';
import 'package:pulsr/core/utils/error_logger.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/per_song_eq_store.dart';
import 'package:pulsr/data/audio/per_song_volume_store.dart';
import 'package:pulsr/data/audio/song_rating_store.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_download_cubit.dart';
import 'package:pulsr/services/discord/discord_rpc_service.dart';
import 'package:pulsr/services/updater/app_update_service.dart';
import 'injection.config.dart';

final GetIt getIt = GetIt.instance;

final Completer<void> _initializationReady = Completer<void>();

/// Completes when [configureDependencies] has finished (or failed). The splash
/// gates its routing on this real signal instead of an arbitrary delay (I25).
Future<void> get initializationReady => _initializationReady.future;

@InjectableInit()
Future<void> configureDependencies() async {
  try {
    getIt.init();
    if (!getIt.isRegistered<DiscordRpcService>()) {
      getIt.registerLazySingleton<DiscordRpcService>(
          () => DiscordRpcService.instance);
    }
    if (!getIt.isRegistered<AppUpdateService>()) {
      getIt.registerLazySingleton<AppUpdateService>(
          () => AppUpdateService.instance);
    }
    // Pre-warm async singletons so sync getIt<T>() in main.dart never throws
    // StateError (audio handler -> player cubit -> download cubit -> intents).
    var audioHandlerReady = false;
    try {
      await getIt
          .getAsync<PulsrAudioHandler>()
          .timeout(const Duration(seconds: 12));
      audioHandlerReady = true;
    } catch (e, st) {
      ErrorLogger.log('PulsrAudioHandler DI warm-up timed out or failed',
          error: e, stackTrace: st, category: 'DI');
    }

    if (audioHandlerReady) {
      try {
        await getIt.getAsync<PlayerCubit>().timeout(const Duration(seconds: 5));
      } catch (e, st) {
        ErrorLogger.log('PlayerCubit DI warm-up timed out or failed',
            error: e, stackTrace: st, category: 'DI');
      }

      // Run post-player warm-up concurrently to reduce cold-start latency.
      await Future.wait<void>([
        if (AppConfig.ytmEnabled)
          _warmUpAsync<YtmDownloadCubit>('YtmDownloadCubit'),
        _warmUpAsync<FileIntentHandler>('FileIntentHandler'),
        _warmUpOverrideStores(),
      ]);

      try {
        await getIt.allReady().timeout(const Duration(seconds: 5));
      } catch (e, st) {
        ErrorLogger.log('getIt.allReady() warm-up timed out or failed',
            error: e, stackTrace: st, category: 'DI');
      }
    } else {
      // Audio handler failed; skip dependent warm-ups to prevent a 27s stall.
      await _warmUpOverrideStores();
    }
    validateDependencies(getIt);
  } finally {
    if (!_initializationReady.isCompleted) _initializationReady.complete();
  }
}

Future<void> _warmUpAsync<T extends Object>(
  String name, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  try {
    if (getIt.isRegistered<T>()) {
      await getIt.getAsync<T>().timeout(timeout);
    }
  } catch (e, st) {
    ErrorLogger.log('$name DI warm-up timed out or failed',
        error: e, stackTrace: st, category: 'DI');
  }
}

Future<void> _warmUpOverrideStores() async {
  try {
    await Future.wait<void>([
      if (getIt.isRegistered<SongRatingStore>()) getIt<SongRatingStore>().ready,
      if (getIt.isRegistered<PerSongEqStore>()) getIt<PerSongEqStore>().ready,
      if (getIt.isRegistered<PerSongVolumeStore>())
        getIt<PerSongVolumeStore>().ready,
    ]).timeout(const Duration(seconds: 5));
  } catch (e, st) {
    ErrorLogger.log('Per-song override store warm-up timed out or failed',
        error: e, stackTrace: st, category: 'DI');
  }
}

void validateDependencies(GetIt getIt) {
  // `assert` is stripped in release builds, so a missing eager singleton only
  // surfaced as a mysterious launch crash (or a null lookup deep in the UI).
  // Throw an explicit [StateError] that survives `--release`.
  void require<T extends Object>() {
    if (!getIt.isRegistered<T>()) {
      throw StateError('${T.toString()} must be registered in DI');
    }
  }

  require<AppDatabase>();
  require<PulsrAudioHandler>();
  require<PlayerCubit>();
  require<DownloadsCubit>();
  if (AppConfig.ytmEnabled) {
    require<YtmDownloadCubit>();
  }
}

bool _isSingletonReady<T extends Object>() {
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

Future<void> _awaitDependency<T extends Object>() async {
  // Sync-registered types (and factories) must not go through getAsync: it
  // rejects non-async registrations with a StateError.
  if (_isSingletonReady<T>()) return;
  if (!getIt.isRegistered<T>()) {
    throw StateError('${T.toString()} is not registered in DI');
  }
  await getIt.getAsync<T>();
}

/// Whether every async singleton the root widget resolves synchronously during
/// its first build is ready. A pending/failed warm-up returns false so the UI
/// can show a recoverable boot screen instead of throwing a StateError.
bool get appDependenciesReady =>
    _isSingletonReady<PulsrAudioHandler>() &&
    _isSingletonReady<PlayerCubit>() &&
    (!AppConfig.ytmEnabled || _isSingletonReady<YtmDownloadCubit>());

/// Awaits the app-shell singletons that [PulsrApp] looks up synchronously.
/// Warm-up failures in [configureDependencies] are swallowed, so this gives a
/// slow or partially failed cold start a second, awaitable chance. Never
/// throws; returns whether the app can render.
Future<bool> ensureAppDependenciesReady({
  Duration timeout = const Duration(seconds: 30),
}) async {
  try {
    await Future.wait<void>([
      _awaitDependency<PulsrAudioHandler>(),
      _awaitDependency<PlayerCubit>(),
      if (AppConfig.ytmEnabled) _awaitDependency<YtmDownloadCubit>(),
    ]).timeout(timeout);
    return true;
  } catch (e, st) {
    ErrorLogger.log('App-shell DI warm-up incomplete',
        error: e, stackTrace: st, category: 'DI');
    return false;
  }
}

FutureOr<void> disposeHttpClient(HttpClient client) {
  client.close(force: false);
}

FutureOr<void> disposePkgHttpClient(http.Client client) {
  client.close();
}

@module
abstract class NetworkModule {
  @Singleton(dispose: disposeHttpClient)
  HttpClient get httpClient => HttpClient()
    ..maxConnectionsPerHost = 5
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 90);

  @Singleton(dispose: disposePkgHttpClient)
  http.Client get pkgHttpClient => http.Client();
}

@module
abstract class StorageModule {
  @lazySingleton
  FlutterSecureStorage get secureStorage => const FlutterSecureStorage(
        aOptions: AndroidOptions(
          resetOnError: true,
        ),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock,
        ),
      );
}
