// test/data/audio/audio_handler_support_test.dart
import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/audio_handler_lifecycle_observer.dart';
import 'package:pulsr/data/audio/multi_output_router.dart';

import 'handler_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MultiOutputRouter', () {
    const channel = MethodChannel('com.pulsr.music/audio_effects');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('system default always succeeds without touching the channel',
        () async {
      final router = MultiOutputRouter();
      expect(await router.setMode(MultiOutputMode.systemDefault), isTrue);
      expect(router.lastRouteSupported, isTrue);
      expect(router.lastError, isNull);
      router.dispose();
    });

    test('a supported vendor route reports success and emits a change',
        () async {
      messenger.setMockMethodCallHandler(channel, (_) async => 'ok');
      final router = MultiOutputRouter();
      final changes = <MultiOutputMode>[];
      final sub = router.changes.listen(changes.add);

      expect(
          await router.setMode(MultiOutputMode.speakerAndBluetooth), isTrue);
      expect(router.isSimultaneous, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(changes, contains(MultiOutputMode.speakerAndBluetooth));

      await sub.cancel();
      router.dispose();
    });

    test('an unsupported vendor route degrades gracefully', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => 'unsupported');
      final router = MultiOutputRouter();
      expect(await router.setMode(MultiOutputMode.bluetoothOnly), isFalse);
      expect(router.lastRouteSupported, isFalse);
      expect(router.lastError, 'unsupported');
      router.dispose();
    });

    test('a platform error is caught and reported', () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'boom');
      });
      final router = MultiOutputRouter();
      expect(await router.setMode(MultiOutputMode.speakerOnly), isFalse);
      expect(router.lastRouteSupported, isFalse);
      router.dispose();
    });
  });

  group('AudioHandlerLifecycleObserver', () {
    test('background fires once across hidden and paused', () {
      var background = 0;
      var resume = 0;
      final observer = AudioHandlerLifecycleObserver(
        onBackground: () => background++,
        onResume: () => resume++,
      );

      observer.didChangeAppLifecycleState(AppLifecycleState.inactive);
      observer.didChangeAppLifecycleState(AppLifecycleState.hidden);
      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(background, 1);

      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(resume, 1);

      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(background, 2);
    });

    test('detached prefers onDetached over onBackground', () {
      var background = 0;
      var detached = 0;
      final observer = AudioHandlerLifecycleObserver(
        onBackground: () => background++,
        onDetached: () => detached++,
      );

      observer.didChangeAppLifecycleState(AppLifecycleState.detached);
      expect(detached, 1);
      expect(background, 0);
    });

    test('hidden prefers onHidden over onBackground', () {
      var background = 0;
      var hidden = 0;
      final observer = AudioHandlerLifecycleObserver(
        onBackground: () => background++,
        onHidden: () => hidden++,
      );

      observer.didChangeAppLifecycleState(AppLifecycleState.hidden);
      expect(hidden, 1);
      expect(background, 0);
    });

    test('detached without a callback falls back to onBackground', () {
      var background = 0;
      final observer = AudioHandlerLifecycleObserver(
        onBackground: () => background++,
      );
      observer.didChangeAppLifecycleState(AppLifecycleState.detached);
      expect(background, 1);
    });
  });

  group('handler main-surface', () {
    final originalPlatform = JustAudioPlatform.instance;
    late MockMusicRepository repo;
    late MockYtmService ytm;
    PulsrAudioHandler? handler;

    setUp(() {
      JustAudioPlatform.instance = FakeJustAudioPlatform();
      installHandlerChannelStubs();
      repo = MockMusicRepository();
      stubDefaultRepository(repo);
      ytm = MockYtmService();
    });

    tearDown(() async {
      await handler?.dispose();
      handler = null;
      removeHandlerChannelStubs();
      JustAudioPlatform.instance = originalPlatform;
    });

    test('setVolume clamps finite values and ignores NaN', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.setVolume(0.4);
      expect(handler!.volume, closeTo(0.4, 0.001));

      await handler!.setVolume(5);
      expect(handler!.volume, closeTo(1.0, 0.001));

      await handler!.setVolume(double.nan);
      expect(handler!.volume, closeTo(1.0, 0.001));
    });

    test('setDvcEnabled reports unsupported native support', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.setDvcEnabled(true);
      expect(handler!.isDvcEnabled, isFalse);
      await handler!.setDvcEnabled(false);
      expect(handler!.isDvcEnabled, isFalse);
    });

    test('getPlatformFocusState reads the native focus flag', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      expect(await handler!.getPlatformFocusState(), isTrue);
    });

    test('onAppPaused and effectsReady complete', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.effectsReady;
      await handler!.onAppPaused();
    });

    test('handleSystemUiSoundInterruption ducks a playing track', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.loadQueue([localSong(1)], autoPlay: true);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await handler!.handleSystemUiSoundInterruption();
      // A second call while ducked is a no-op.
      await handler!.handleSystemUiSoundInterruption();
    });

    test('withSmoothDspTransition runs the action', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      final result =
          await handler!.withSmoothDspTransition(() async => 42);
      expect(result, 42);
    });

    test('setRating mirrors the heart onto the current song', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.loadQueue([localSong(1)], autoPlay: false);
      await handler!.setRating(Rating.newHeartRating(true));
      expect(handler!.currentSong?.isFavorite, isTrue);
    });

    test('stop is idempotent and dispose is idempotent', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.stop();
      await handler!.dispose();
      expect(handler!.isDisposed, isTrue);
      await handler!.dispose();
      handler = null;
    });
  });
}
