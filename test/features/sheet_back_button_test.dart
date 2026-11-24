import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/config/app_config.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/router/app_router.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/theme/dynamic_theme_cubit.dart';
import 'package:pulsr/core/widgets/pulsr_adaptive_sheet.dart';
import 'package:pulsr/core/widgets/pulsr_bottom_sheet.dart';
import 'package:pulsr/core/widgets/pulsr_modal_tracker.dart';
import 'package:pulsr/core/widgets/pulsr_page_pop_scope.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/now_playing_screen.dart';
import 'package:pulsr/features/player/presentation/widgets/audio_visualizer.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/shell/presentation/app_shell.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_song_factory.dart';

class _MockPlayerCubit extends Mock implements PlayerCubit {}

class _MockSettingsCubit extends Mock implements SettingsCubit {}

class _MockDynamicThemeCubit extends Mock implements DynamicThemeCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockPlayerCubit playerCubit;
  late _MockSettingsCubit settingsCubit;
  late _MockDynamicThemeCubit dynamicThemeCubit;
  late StreamController<PlayerState> playerStreamController;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.lastSeenAppVersion: AppConfig.appVersion,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    AudioVisualizer.isTestingOverride = true;

    playerStreamController = StreamController<PlayerState>.broadcast();
    playerCubit = _MockPlayerCubit();
    when(() => playerCubit.state).thenReturn(const PlayerState());
    when(() => playerCubit.stream)
        .thenAnswer((_) => playerStreamController.stream);
    when(() => playerCubit.resetOverlayViews()).thenReturn(null);

    settingsCubit = _MockSettingsCubit();
    when(() => settingsCubit.state).thenReturn(const SettingsState());
    when(() => settingsCubit.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());

    dynamicThemeCubit = _MockDynamicThemeCubit();
    when(() => dynamicThemeCubit.state).thenReturn(const DynamicThemeState());
    when(() => dynamicThemeCubit.stream)
        .thenAnswer((_) => const Stream<DynamicThemeState>.empty());
    when(() => dynamicThemeCubit.updateFromSong(any()))
        .thenAnswer((_) async {});
  });

  tearDown(() async {
    AudioVisualizer.isTestingOverride = null;
    await playerStreamController.close();
  });

  Future<void> teardownRouterApp(
    WidgetTester tester,
    GoRouter router,
  ) async {
    final nav = rootNavigatorKey.currentState;
    if (nav != null) {
      while (nav.canPop()) {
        nav.pop();
        await tester.pump();
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    router.dispose();
  }

  testWidgets(
      'system back closes PulsrSheetHelper sheet on StatefulShellRoute tab without switching tabs or leaving page',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late StatefulNavigationShell capturedShell;
    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      observers: [PulsrModalObserver()],
      initialLocation: '/',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            capturedShell = navigationShell;
            return AppShell(navigationShell: navigationShell);
          },
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) => const Scaffold(
                    body: Center(child: Text('Home Tab')),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/library',
                  builder: (context, state) => Scaffold(
                    body: Center(
                      child: ElevatedButton(
                        onPressed: () {
                          PulsrSheetHelper.showPulsrSheet<void>(
                            context: context,
                            builder: (_) => const SizedBox(
                              height: 200,
                              child: Center(child: Text('Library Sheet')),
                            ),
                          );
                        },
                        child: const Text('Open Library Sheet'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<PlayerCubit>.value(value: playerCubit),
          BlocProvider<SettingsCubit>.value(value: settingsCubit),
          BlocProvider<DynamicThemeCubit>.value(value: dynamicThemeCubit),
        ],
        child: MaterialApp.router(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Library tab via goBranch so AppShell tracks tab index 1.
    capturedShell.goBranch(1);
    await tester.pumpAndSettle();
    expect(capturedShell.currentIndex, 1);
    expect(find.text('Open Library Sheet'), findsOneWidget);

    // Open modal sheet from Library tab.
    await tester.tap(find.text('Open Library Sheet'));
    await tester.pumpAndSettle();
    expect(find.text('Library Sheet'), findsOneWidget);
    expect(PulsrModalTracker.isModalOpen.value, isTrue);

    // System back closes ONLY the sheet and stays on Library tab.
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);
    expect(find.text('Library Sheet'), findsNothing);
    expect(PulsrModalTracker.isModalOpen.value, isFalse);
    expect(capturedShell.currentIndex, 1);
    expect(find.text('Open Library Sheet'), findsOneWidget);

    await teardownRouterApp(tester, router);
  });

  testWidgets(
      'system back closes PulsrSheetHelper sheet on pushed PulsrPagePopScope detail route without popping page',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      observers: [PulsrModalObserver()],
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push('/detail'),
                child: const Text('Push Detail'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/detail',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => PulsrPagePopScope(
            child: Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    PulsrSheetHelper.showPulsrSheet<void>(
                      context: context,
                      builder: (_) => const SizedBox(
                        height: 200,
                        child: Center(child: Text('Detail Sheet')),
                      ),
                    );
                  },
                  child: const Text('Open Detail Sheet'),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Push Detail'));
    await tester.pumpAndSettle();
    expect(find.text('Open Detail Sheet'), findsOneWidget);

    await tester.tap(find.text('Open Detail Sheet'));
    await tester.pumpAndSettle();
    expect(find.text('Detail Sheet'), findsOneWidget);
    expect(PulsrModalTracker.isModalOpen.value, isTrue);

    // First back closes ONLY the sheet.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Detail Sheet'), findsNothing);
    expect(PulsrModalTracker.isModalOpen.value, isFalse);
    expect(find.text('Open Detail Sheet'), findsOneWidget);

    // Second back pops the detail page back to home.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Open Detail Sheet'), findsNothing);
    expect(find.text('Push Detail'), findsOneWidget);

    await teardownRouterApp(tester, router);
  });

  testWidgets(
      'system back closes PulsrAdaptiveSheet on pushed PulsrPagePopScope detail route without popping page',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      observers: [PulsrModalObserver()],
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push('/detail'),
                child: const Text('Push Detail'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/detail',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => PulsrPagePopScope(
            child: Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    PulsrAdaptiveSheet.show<void>(
                      context: context,
                      titleText: 'Adaptive Title',
                      builder: (_) => const SizedBox(
                        height: 200,
                        child: Center(child: Text('Adaptive Body')),
                      ),
                    );
                  },
                  child: const Text('Open Adaptive Sheet'),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Push Detail'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Adaptive Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Adaptive Body'), findsOneWidget);
    expect(PulsrModalTracker.isModalOpen.value, isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Adaptive Body'), findsNothing);
    expect(PulsrModalTracker.isModalOpen.value, isFalse);
    expect(find.text('Open Adaptive Sheet'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Push Detail'), findsOneWidget);

    await teardownRouterApp(tester, router);
  });

  testWidgets(
      'system back closes PulsrSheetHelper sheet on Android PredictiveBack without popping PulsrPagePopScope page',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      observers: [PulsrModalObserver()],
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: Scaffold(
              body: Center(
                child: Builder(
                  builder: (buttonContext) => ElevatedButton(
                    onPressed: () => buttonContext.push('/detail'),
                    child: const Text('Push Android Detail'),
                  ),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/detail',
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (context, state) => MaterialPage<void>(
            key: state.pageKey,
            child: PulsrPagePopScope(
              child: Scaffold(
                body: Center(
                  child: Builder(
                    builder: (buttonContext) => ElevatedButton(
                      onPressed: () {
                        PulsrSheetHelper.showPulsrSheet<void>(
                          context: buttonContext,
                          builder: (_) => const SizedBox(
                            height: 200,
                            child: Center(child: Text('Android Sheet')),
                          ),
                        );
                      },
                      child: const Text('Open Android Sheet'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Push Android Detail'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Android Sheet'));
    await tester.pumpAndSettle();
    expect(find.text('Android Sheet'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Android Sheet'), findsNothing);
    expect(find.text('Open Android Sheet'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Push Android Detail'), findsOneWidget);

    await teardownRouterApp(tester, router);
  });

  testWidgets(
      'AppShell.handlePop respects inner PopScope on root modal sheets instead of force-popping',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var allowSheetPop = false;
    var interceptedCount = 0;

    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      observers: [PulsrModalObserver()],
      initialLocation: '/',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              AppShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) => Scaffold(
                    body: Center(
                      child: ElevatedButton(
                        onPressed: () {
                          PulsrSheetHelper.showPulsrSheet<void>(
                            context: context,
                            builder: (_) => StatefulBuilder(
                              builder: (ctx, setSheetState) => PopScope(
                                canPop: allowSheetPop,
                                onPopInvokedWithResult: (didPop, _) {
                                  if (didPop) return;
                                  setSheetState(() {
                                    interceptedCount++;
                                    allowSheetPop = true;
                                  });
                                },
                                child: const SizedBox(
                                  height: 200,
                                  child: Center(
                                      child: Text('Guarded Modal Sheet')),
                                ),
                              ),
                            ),
                          );
                        },
                        child: const Text('Open Guarded Sheet'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<PlayerCubit>.value(value: playerCubit),
          BlocProvider<SettingsCubit>.value(value: settingsCubit),
          BlocProvider<DynamicThemeCubit>.value(value: dynamicThemeCubit),
        ],
        child: MaterialApp.router(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Guarded Sheet'));
    await tester.pumpAndSettle();
    expect(find.text('Guarded Modal Sheet'), findsOneWidget);

    final shellState = tester.state<AppShellState>(find.byType(AppShell));

    // First pop invokes AppShell.handlePop -> maybePop respects canPop: false
    // and flips allowSheetPop to true rather than force-popping.
    await shellState.handlePop(ignoreThrottle: true);
    await tester.pumpAndSettle();
    expect(interceptedCount, 1);
    expect(find.text('Guarded Modal Sheet'), findsOneWidget);

    // Second pop closes the sheet.
    await shellState.handlePop(ignoreThrottle: true);
    await tester.pumpAndSettle();
    expect(find.text('Guarded Modal Sheet'), findsNothing);
    expect(PulsrModalTracker.isModalOpen.value, isFalse);

    await teardownRouterApp(tester, router);
  });

  testWidgets(
      'NowPlayingScreen back button closes modal sheet first, then Lyrics/Queue overlay, then pops NowPlayingScreen',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final testSong = createTestSong(
      id: 42,
      title: 'Test Track',
      artist: 'Test Artist',
      album: 'Test Album',
      durationMs: 180000,
    );

    var currentState = PlayerState(
      playback: PlaybackSlice(
        currentSong: testSong,
        isPlaying: true,
        duration: const Duration(minutes: 3),
        position: const Duration(seconds: 20),
      ),
      queueSlice: QueueSlice(
        queue: [testSong],
        currentIndex: 0,
      ),
      lyricsSlice: const LyricsSlice(
        isLyricsVisible: true,
        lyrics: [LyricsLine(timestamp: Duration(seconds: 5), text: 'Line 1')],
      ),
    );

    when(() => playerCubit.state).thenAnswer((_) => currentState);
    when(() => playerCubit.resetOverlayViews()).thenAnswer((_) {
      currentState = currentState.copyWith.lyricsSlice(
        isLyricsVisible: false,
        isQueueVisible: false,
      );
      playerStreamController.add(currentState);
    });

    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      observers: [PulsrModalObserver()],
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push('/now-playing'),
                child: const Text('Open Now Playing'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/now-playing',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const NowPlayingScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<PlayerCubit>.value(value: playerCubit),
          BlocProvider<SettingsCubit>.value(value: settingsCubit),
          BlocProvider<DynamicThemeCubit>.value(value: dynamicThemeCubit),
        ],
        child: MaterialApp.router(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Now Playing'));
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingScreen), findsOneWidget);

    // Open a modal sheet on top of NowPlayingScreen.
    final nowPlayingCtx = tester.element(find.byType(NowPlayingScreen));
    unawaited(
      PulsrSheetHelper.showPulsrSheet<void>(
        context: nowPlayingCtx,
        builder: (_) => const SizedBox(
          height: 200,
          child: Center(child: Text('Player Modal Sheet')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Player Modal Sheet'), findsOneWidget);
    expect(PulsrModalTracker.isModalOpen.value, isTrue);

    // 1st back press: closes ONLY the modal sheet, keeps overlay and NowPlaying.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Player Modal Sheet'), findsNothing);
    expect(PulsrModalTracker.isModalOpen.value, isFalse);
    expect(find.byType(NowPlayingScreen), findsOneWidget);
    verifyNever(() => playerCubit.resetOverlayViews());

    // 2nd back press: closes Lyrics overlay without popping NowPlayingScreen.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    verify(() => playerCubit.resetOverlayViews()).called(1);
    expect(find.byType(NowPlayingScreen), findsOneWidget);
    expect(currentState.isLyricsVisible, isFalse);

    // Open Queue overlay and confirm back closes Queue overlay before popping.
    currentState = currentState.copyWith.lyricsSlice(isQueueVisible: true);
    playerStreamController.add(currentState);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    verify(() => playerCubit.resetOverlayViews()).called(1);
    expect(find.byType(NowPlayingScreen), findsOneWidget);
    expect(currentState.isQueueVisible, isFalse);

    // Final back press: pops NowPlayingScreen back to '/'.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingScreen), findsNothing);
    expect(find.text('Open Now Playing'), findsOneWidget);

    await teardownRouterApp(tester, router);
  });

  testWidgets(
      'Android predictive back gesture closes PulsrSheetHelper sheet on StatefulShellRoute tab without leaving tab',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late StatefulNavigationShell capturedShell;
    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      observers: [PulsrModalObserver()],
      initialLocation: '/',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            capturedShell = navigationShell;
            return AppShell(navigationShell: navigationShell);
          },
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) => const Scaffold(
                    body: Center(child: Text('Home Tab')),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/settings',
                  builder: (context, state) => Scaffold(
                    body: Center(
                      child: ElevatedButton(
                        onPressed: () {
                          PulsrSheetHelper.showPulsrSheet<void>(
                            context: context,
                            builder: (_) => const SizedBox(
                              height: 200,
                              child: Center(child: Text('Settings Sheet')),
                            ),
                          );
                        },
                        child: const Text('Open Settings Sheet'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<PlayerCubit>.value(value: playerCubit),
          BlocProvider<SettingsCubit>.value(value: settingsCubit),
          BlocProvider<DynamicThemeCubit>.value(value: dynamicThemeCubit),
        ],
        child: MaterialApp.router(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    capturedShell.goBranch(1);
    await tester.pumpAndSettle();
    expect(capturedShell.currentIndex, 1);

    await tester.tap(find.text('Open Settings Sheet'));
    await tester.pumpAndSettle();
    expect(find.text('Settings Sheet'), findsOneWidget);
    expect(PulsrModalTracker.isModalOpen.value, isTrue);

    // Simulate Android 14+ predictive back gesture via SystemChannels.backGesture
    final codec = const StandardMethodCodec();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      SystemChannels.backGesture.name,
      codec.encodeMethodCall(const MethodCall('startBackGesture', {
        'touchOffset': [0.0, 400.0],
        'progress': 0.0,
        'swipeEdge': 0,
      })),
      (_) {},
    );
    await tester.pump();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      SystemChannels.backGesture.name,
      codec.encodeMethodCall(const MethodCall('commitBackGesture')),
      (_) {},
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings Sheet'), findsNothing);
    expect(PulsrModalTracker.isModalOpen.value, isFalse);
    expect(capturedShell.currentIndex, 1);
    expect(find.text('Open Settings Sheet'), findsOneWidget);

    await teardownRouterApp(tester, router);
  });

  testWidgets(
      'system back closes Equalizer-style sheet opened on context.push(/settings) branch without popping Settings',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      observers: [PulsrModalObserver()],
      initialLocation: '/',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return AppShell(navigationShell: navigationShell);
          },
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) => Scaffold(
                    body: Center(
                      child: ElevatedButton(
                        onPressed: () => context.push('/settings'),
                        child: const Text('Push Settings'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/settings',
                  builder: (context, state) => Scaffold(
                    body: Center(
                      child: ElevatedButton(
                        onPressed: () {
                          PulsrSheetHelper.showPulsrSheet<void>(
                            context: context,
                            wrapWithContainer: false,
                            builder: (_) => const SizedBox(
                              height: 300,
                              child: Center(child: Text('Equalizer Sheet')),
                            ),
                          );
                        },
                        child: const Text('Open Equalizer Sheet'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<PlayerCubit>.value(value: playerCubit),
          BlocProvider<SettingsCubit>.value(value: settingsCubit),
          BlocProvider<DynamicThemeCubit>.value(value: dynamicThemeCubit),
        ],
        child: MaterialApp.router(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Push Settings branch just like HomeScreen's settings gear icon.
    await tester.tap(find.text('Push Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Open Equalizer Sheet'), findsOneWidget);

    // Open Equalizer-style modal sheet on top of pushed Settings branch.
    await tester.tap(find.text('Open Equalizer Sheet'));
    await tester.pumpAndSettle();
    expect(find.text('Equalizer Sheet'), findsOneWidget);
    expect(PulsrModalTracker.isModalOpen.value, isTrue);

    // 1st back closes ONLY the sheet; Settings stays open!
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Equalizer Sheet'), findsNothing);
    expect(PulsrModalTracker.isModalOpen.value, isFalse);
    expect(find.text('Open Equalizer Sheet'), findsOneWidget);

    // 2nd back leaves Settings back to Home.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Open Equalizer Sheet'), findsNothing);
    expect(find.text('Push Settings'), findsOneWidget);

    await teardownRouterApp(tester, router);
  });
}
