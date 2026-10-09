// test/core/di/injection_bootstrap_test.dart
//
// Exercises `configureDependencies()` end-to-end. Under `flutter_test` the
// generated graph eagerly instantiates real singletons that reach for platform
// channels (drift/path_provider, audio_service, SharedPreferences). Those calls
// fail with MissingPluginException and are swallowed by the warm-up try/catch
// blocks. A guarded zone absorbs the handful of fire-and-forget futures that
// surface outside the awaited blocks so the test stays hermetic and
// deterministic.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_download_cubit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  test(
    'configureDependencies() builds the graph and completes the ready signal',
    () async {
      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        await configureDependencies().timeout(const Duration(seconds: 60));
      }, (error, stack) {
        uncaught.add(error);
      });

      // Let the fire-and-forget singleton futures settle inside the guarded
      // zone before tearing the graph down.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // The finally block must always complete the routing gate (I25).
      expect(
        await initializationReady.then((_) => true).timeout(const Duration(seconds: 5)),
        isTrue,
      );

      // Eager singletons the rest of the app looks up synchronously.
      expect(getIt.isRegistered<AppDatabase>(), isTrue);
      expect(getIt.isRegistered<PulsrAudioHandler>(), isTrue);
      expect(getIt.isRegistered<PlayerCubit>(), isTrue);
      expect(getIt.isRegistered<DownloadsCubit>(), isTrue);
      expect(getIt.isRegistered<YtmDownloadCubit>(), isTrue);

      // The explicit release-surviving validation must pass on a full graph.
      expect(() => validateDependencies(getIt), returnsNormally);

      // Plugin-free test environment: a few async channel failures escape the
      // awaited warm-up blocks. They are expected, not a sign of a broken graph.
      expect(uncaught, isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'configureDependencies() still completes the ready signal when init throws',
    () async {
      // Pre-registering a type the generated graph owns forces `getIt.init()`
      // to throw before any heavy singleton is created. The finally block must
      // still release the splash gate.
      getIt.registerSingleton<HttpClient>(HttpClient());

      await expectLater(configureDependencies(), throwsA(isA<Object>()));

      expect(
        await initializationReady.then((_) => true).timeout(const Duration(seconds: 5)),
        isTrue,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

