import 'dart:async';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

import 'package:pulsr/core/services/file_intent_handler.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/per_song_eq_store.dart';
import 'package:pulsr/data/audio/per_song_volume_store.dart';
import 'package:pulsr/data/audio/song_rating_store.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_download_cubit.dart';
import 'injection.config.dart';

final GetIt getIt = GetIt.instance;

@InjectableInit()
Future<void> configureDependencies() async {
  getIt.init();
  // Pre-warm async singletons so sync getIt<T>() in main.dart never throws
  // StateError (audio handler -> player cubit -> download cubit -> intents).
  try {
    await getIt
        .getAsync<PulsrAudioHandler>()
        .timeout(const Duration(seconds: 12));
  } catch (_) {}
  try {
    await getIt.getAsync<PlayerCubit>().timeout(const Duration(seconds: 5));
  } catch (_) {}
  try {
    await getIt
        .getAsync<YtmDownloadCubit>()
        .timeout(const Duration(seconds: 5));
  } catch (_) {}
  try {
    await getIt
        .getAsync<FileIntentHandler>()
        .timeout(const Duration(seconds: 5));
  } catch (_) {}
  // Per-song override stores load their SharedPreferences map asynchronously
  // in their constructors; sync getters (player cubit per-track sync, smart
  // playlist filters, song-info sheet) must never observe the empty pre-load
  // map. Await their `ready` futures so the first UI read is authoritative.
  try {
    await Future.wait<void>([
      getIt<SongRatingStore>().ready,
      getIt<PerSongEqStore>().ready,
      getIt<PerSongVolumeStore>().ready,
    ]).timeout(const Duration(seconds: 5));
  } catch (_) {}
  try {
    await getIt.allReady().timeout(const Duration(seconds: 5));
  } catch (_) {}
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
