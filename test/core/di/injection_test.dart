// test/core/di/injection_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_download_cubit.dart';

class _MockAppDatabase extends Mock implements AppDatabase {}

class _MockAudioHandler extends Mock implements PulsrAudioHandler {}

class _MockPlayerCubit extends Mock implements PlayerCubit {}

class _MockDownloadsCubit extends Mock implements DownloadsCubit {}

class _MockYtmDownloadCubit extends Mock implements YtmDownloadCubit {}

class _TestNetworkModule extends NetworkModule {}

class _TestStorageModule extends StorageModule {}

void main() {
  group('validateDependencies', () {
    test('passes when every required type is registered', () {
      final getIt = GetIt.asNewInstance();
      getIt.registerSingleton<AppDatabase>(_MockAppDatabase());
      getIt.registerSingleton<PulsrAudioHandler>(_MockAudioHandler());
      getIt.registerSingleton<PlayerCubit>(_MockPlayerCubit());
      getIt.registerSingleton<DownloadsCubit>(_MockDownloadsCubit());
      getIt.registerSingleton<YtmDownloadCubit>(_MockYtmDownloadCubit());
      addTearDown(getIt.reset);

      expect(() => validateDependencies(getIt), returnsNormally);
    });

    test('throws a StateError naming the first missing registration', () {
      final getIt = GetIt.asNewInstance();
      addTearDown(getIt.reset);

      expect(
        () => validateDependencies(getIt),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('AppDatabase'))),
      );

      getIt.registerSingleton<AppDatabase>(_MockAppDatabase());
      expect(
        () => validateDependencies(getIt),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('PulsrAudioHandler'))),
      );
    });
  });

  group('dispose helpers', () {
    test('disposeHttpClient closes the dart:io client', () {
      final client = HttpClient();
      expect(disposeHttpClient(client), isNull);
    });

    test('disposePkgHttpClient closes the package client', () {
      final client = http.Client();
      expect(disposePkgHttpClient(client), isNull);
    });
  });

  group('NetworkModule', () {
    test('httpClient is tuned and pkgHttpClient is a real client', () {
      final module = _TestNetworkModule();
      final ioClient = module.httpClient;
      expect(ioClient.maxConnectionsPerHost, 5);
      expect(ioClient.connectionTimeout, const Duration(seconds: 15));
      expect(ioClient.idleTimeout, const Duration(seconds: 90));
      disposeHttpClient(ioClient);

      final pkgClient = module.pkgHttpClient;
      expect(pkgClient, isA<http.Client>());
      disposePkgHttpClient(pkgClient);
    });
  });

  group('StorageModule', () {
    test('exposes a secure storage instance', () {
      expect(_TestStorageModule().secureStorage, isNotNull);
    });
  });

  test('initializationReady is a future signal', () {
    expect(initializationReady, isA<Future<void>>());
  });
}
