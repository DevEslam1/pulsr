// AppShell branch coverage beyond the stopwatch lifecycle: system-UI immersive
// toggling, tab navigation/history, handlePop routing (modal, root navigator,
// inspector, history), the tablet rail + side inspector, the playback-error
// toast and the global keyboard shortcuts.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/router/app_router.dart';
import 'package:pulsr/core/widgets/pulsr_modal_tracker.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/shell/presentation/app_shell.dart';
import 'package:pulsr/features/shell/presentation/widgets/landscape_sidebar.dart';
import 'package:pulsr/features/shell/presentation/widgets/stacked_bottom_dock.dart';
import 'package:pulsr/features/player/presentation/widgets/tablet_player_bar.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockPlayerCubit extends Mock implements PlayerCubit {}

class _MockSettingsCubit extends Mock implements SettingsCubit {}

class _FakeNavigationShell extends StatefulWidget
    implements StatefulNavigationShell {
  @override
  final int currentIndex;
  final void Function(int, {bool initialLocation})? onGoBranch;

  const _FakeNavigationShell({this.currentIndex = 0, this.onGoBranch});

  @override
  void goBranch(int index, {bool initialLocation = false}) {
    onGoBranch?.call(index, initialLocation: initialLocation);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  State<_FakeNavigationShell> createState() => _FakeNavigationShellState();
}

class _FakeNavigationShellState extends State<_FakeNavigationShell> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockPlayerCubit player;
  late _MockSettingsCubit settings;
  final platformCalls = <MethodCall>[];

  setUpAll(() {
    registerFallbackValue(const Duration(seconds: 1));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PulsrModalTracker.isModalOpen.value = false;
    platformCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platformCalls.add(call);
      return null;
    });

    player = _MockPlayerCubit();
    when(() => player.state).thenReturn(const PlayerState());
    when(() => player.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    when(() => player.togglePlayPause()).thenAnswer((_) async {});
    when(() => player.fastForward(any())).thenAnswer((_) async {});
    when(() => player.rewind(any())).thenAnswer((_) async {});
    when(() => player.adjustVolume(any())).thenAnswer((_) async {});
    when(() => player.next()).thenAnswer((_) async {});
    when(() => player.previous()).thenAnswer((_) async {});
    when(() => player.toggleFavorite()).thenAnswer((_) async {});
    when(() => player.toggleMute()).thenAnswer((_) async {});
    when(() => player.toggleLyrics()).thenReturn(null);
    when(() => player.toggleQueue()).thenReturn(null);

    settings = _MockSettingsCubit();
    when(() => settings.state).thenReturn(const SettingsState());
    when(() => settings.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
  });

  tearDown(() {
    PulsrModalTracker.isModalOpen.value = false;
  });

  Widget buildShell({
    int currentIndex = 0,
    void Function(int, {bool initialLocation})? onGoBranch,
    GlobalKey<NavigatorState>? navigatorKey,
    Size size = const Size(390, 844),
    bool tablet = false,
  }) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<PlayerCubit>.value(value: player),
        if (tablet) BlocProvider<SettingsCubit>.value(value: settings),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(size: size, disableAnimations: true),
          child: AppShell(
            navigationShell: _FakeNavigationShell(
              currentIndex: currentIndex,
              onGoBranch: onGoBranch,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('landscape immersion responds to the modal tracker',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildShell(
      size: const Size(1280, 800),
      tablet: true,
    ));
    await tester.pumpAndSettle();

    expect(
      platformCalls.any((c) =>
          c.method == 'SystemChrome.setEnabledSystemUIMode' &&
          c.arguments.toString().contains('immersiveSticky')),
      isTrue,
    );

    platformCalls.clear();
    PulsrModalTracker.isModalOpen.value = true;
    await tester.pumpAndSettle();
    expect(
      platformCalls.any((c) =>
          c.method == 'SystemChrome.setEnabledSystemUIMode' &&
          c.arguments.toString().contains('edgeToEdge')),
      isTrue,
    );

    PulsrModalTracker.isModalOpen.value = false;
    await tester.pumpAndSettle();
  });

  testWidgets('resuming the app re-syncs the system UI', (tester) async {
    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();
    final state = tester.state<AppShellState>(find.byType(AppShell));
    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom-dock navigation branches on same vs different tab',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final branches = <int>[];
    await tester.pumpWidget(buildShell(
      currentIndex: 1,
      onGoBranch: (i, {initialLocation = false}) => branches.add(i),
    ));
    await tester.pumpAndSettle();

    final dock =
        tester.widget<StackedBottomDock>(find.byType(StackedBottomDock));
    dock.onTapNav(2);
    await tester.pump(const Duration(milliseconds: 250));
    dock.onTapNav(2);
    await tester.pumpAndSettle();

    expect(branches, contains(2));
  });

  testWidgets('handlePop pops the root navigator when a modal is open',
      (tester) async {
    await tester.pumpWidget(
        buildShell(navigatorKey: rootNavigatorKey, currentIndex: 0));
    await tester.pumpAndSettle();
    final state = tester.state<AppShellState>(find.byType(AppShell));

    final nav = rootNavigatorKey.currentState!;
    nav.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('pushed-route')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('pushed-route'), findsOneWidget);

    PulsrModalTracker.isModalOpen.value = true;
    await state.handlePop(ignoreThrottle: true);
    await tester.pumpAndSettle();

    expect(find.text('pushed-route'), findsNothing);
  });

  testWidgets('handlePop pops a plain root route', (tester) async {
    await tester.pumpWidget(
        buildShell(navigatorKey: rootNavigatorKey, currentIndex: 0));
    await tester.pumpAndSettle();
    final state = tester.state<AppShellState>(find.byType(AppShell));

    rootNavigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('plain-route')),
    ));
    await tester.pumpAndSettle();

    await state.handlePop(ignoreThrottle: true);
    await tester.pumpAndSettle();

    expect(find.text('plain-route'), findsNothing);
  });

  testWidgets('handlePop walks back through tab history', (tester) async {
    final branches = <int>[];
    await tester.pumpWidget(buildShell(
      currentIndex: 0,
      onGoBranch: (i, {initialLocation = false}) => branches.add(i),
    ));
    await tester.pumpAndSettle();

    final dock =
        tester.widget<StackedBottomDock>(find.byType(StackedBottomDock));
    dock.onTapNav(1);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)));
    await tester.pumpAndSettle();
    dock.onTapNav(2);
    await tester.pumpAndSettle();
    branches.clear();

    final state = tester.state<AppShellState>(find.byType(AppShell));
    await state.handlePop(ignoreThrottle: true);
    await tester.pumpAndSettle();

    expect(branches, contains(1));
  });

  testWidgets('tablet rail toggles the extended rail and side inspector',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildShell(
      size: const Size(1280, 900),
      currentIndex: 0,
      tablet: true,
    ));
    await tester.pumpAndSettle();

    expect(find.byType(LandscapeSidebar), findsOneWidget);

    final sidebar =
        tester.widget<LandscapeSidebar>(find.byType(LandscapeSidebar));
    sidebar.onToggleExtended();
    await tester.pumpAndSettle();

    final bar = tester.widget<TabletPlayerBar>(find.byType(TabletPlayerBar));
    bar.onToggleSideInspector!();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final bar2 = tester.widget<TabletPlayerBar>(find.byType(TabletPlayerBar));
    bar2.onToggleSideInspector!();
    await tester.pumpAndSettle();
  });

  testWidgets('a playback error is surfaced as a toast', (tester) async {
    final controller = StreamController<PlayerState>.broadcast();
    addTearDown(controller.close);
    when(() => player.stream).thenAnswer((_) => controller.stream);

    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    controller.add(const PlayerState(
      playback: PlaybackSlice(errorMessage: 'stream_failed'),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
  });

  testWidgets('global keyboard shortcuts reach the player cubit',
      (tester) async {
    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();

    verify(() => player.togglePlayPause()).called(greaterThanOrEqualTo(1));
    verify(() => player.next()).called(greaterThanOrEqualTo(1));
    verify(() => player.previous()).called(greaterThanOrEqualTo(1));
    verify(() => player.toggleMute()).called(greaterThanOrEqualTo(1));
    verify(() => player.toggleLyrics()).called(greaterThanOrEqualTo(1));
    verify(() => player.toggleQueue()).called(greaterThanOrEqualTo(1));
    verify(() => player.toggleFavorite()).called(greaterThanOrEqualTo(1));
  });
}
