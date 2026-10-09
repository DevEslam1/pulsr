// Shared harness for full-screen widget tests.
//
// Every screen under test is wrapped in a MaterialApp.router served by a
// GoRouter (the screens use `context.push`/`GoRouter.of` directly), the Aura
// theme so `context.palette` resolves, and the generated localizations so
// `context.l10n` resolves. Callers pass the BlocProviders the screen reads.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

/// A PlayerCubit stub that always reports [state] and yields no state events.
PlayerCubit stubPlayerCubit([PlayerState? state]) {
  final cubit = MockPlayerCubit();
  when(() => cubit.state).thenReturn(state ?? const PlayerState());
  when(() => cubit.stream)
      .thenAnswer((_) => const Stream<PlayerState>.empty());
  return cubit;
}

/// Resizes the actual test viewport so tall scrollable screens build the
/// widgets below the fold (a MediaQuery override alone does not change layout
/// constraints).
void useScreenSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// The set of destinations the target screens navigate to. They render a
/// trivial placeholder so navigation taps never throw.
List<GoRoute> fakeScreenRoutes() => [
      GoRoute(
          path: '/playlist',
          builder: (_, __) => const Scaffold(body: Text('playlist-route'))),
      GoRoute(
          path: '/favorites',
          builder: (_, __) => const Scaffold(body: Text('favorites-route'))),
      GoRoute(
          path: '/smart-playlist-builder',
          builder: (_, __) =>
              const Scaffold(body: Text('smart-playlist-builder-route'))),
      GoRoute(
          path: '/online-playlist',
          builder: (_, __) =>
              const Scaffold(body: Text('online-playlist-route'))),
      GoRoute(
          path: '/library',
          builder: (_, __) => const Scaffold(body: Text('library-route'))),
      GoRoute(
          path: '/artist',
          builder: (_, __) => const Scaffold(body: Text('artist-route'))),
      GoRoute(
          path: '/album',
          builder: (_, __) => const Scaffold(body: Text('album-route'))),
    ];

/// Wraps [child] with theme, localizations, a minimal GoRouter and [providers].
Widget screenHarness({
  required Widget child,
  List<BlocProvider> providers = const [],
  Size size = const Size(800, 1200),
}) {
  final router = GoRouter(
    initialLocation: '/target',
    routes: [
      // A root page so a screen that calls Navigator.pop() has somewhere to
      // return to instead of trying to pop the only/deepest page.
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
        routes: [
          GoRoute(path: 'target', builder: (_, __) => child),
        ],
      ),
      ...fakeScreenRoutes(),
    ],
  );

  final Widget app = MediaQuery(
    data: MediaQueryData(size: size, disableAnimations: true),
    child: MaterialApp.router(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );

  if (providers.isEmpty) return app;
  return MultiBlocProvider(providers: providers, child: app);
}
