import 'dart:async';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import '../telemetry/clock.dart';
import '../telemetry/playback_latency_tracker.dart';

import 'injection.config.dart';

final GetIt getIt = GetIt.instance;

@InjectableInit()
Future<void> configureDependencies() async {
  getIt.init();
  await getIt.allReady();
}

FutureOr<void> disposeHttpClient(HttpClient client) {
  client.close(force: false);
}

@module
abstract class NetworkModule {
  @Singleton(dispose: disposeHttpClient)
  HttpClient get httpClient => HttpClient()
    ..maxConnectionsPerHost = 5
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 90);

  @singleton
  http.Client get pkgHttpClient => http.Client();
}

@module
abstract class StorageModule {
  @lazySingleton
  FlutterSecureStorage get secureStorage => const FlutterSecureStorage(
        // ignore: deprecated_member_use_from_same_package, deprecated_member_use
        aOptions: AndroidOptions(
          // ignore: deprecated_member_use
          encryptedSharedPreferences: true,
          resetOnError: true,
        ),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock,
        ),
      );
}
