// lib/core/di/injection.dart
import 'dart:io';

import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'injection.config.dart';

final GetIt getIt = GetIt.instance;

@InjectableInit()
Future<void> configureDependencies() async => getIt.init();

@module
abstract class NetworkModule {
  @singleton
  HttpClient get httpClient => HttpClient()..connectionTimeout = const Duration(seconds: 10);
}
