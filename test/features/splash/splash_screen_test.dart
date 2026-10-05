import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/splash/presentation/splash_screen.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l10n = lookupAppLocalizations(const Locale('en'));

  setUp(() async {
    await getIt.reset();
    _messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
  });

  tearDown(() async {
    _messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    await getIt.reset();
  });

  Widget buildApp() {
    final router = GoRouter(
      initialLocation: '/splash',
      routes: [
        GoRoute(
          path: '/splash',
          builder: (context, state) => const SplashScreen(),
        ),
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: Text('HOME_SCREEN')),
        ),
        GoRoute(
          path: '/onboarding',
          builder: (context, state) =>
              const Scaffold(body: Text('ONBOARDING_SCREEN')),
        ),
      ],
    );

    return MaterialApp.router(
      theme: AuraTheme.darkTheme,
      routerConfig: router,
    );
  }

  testWidgets('renders brand title and tagline before routing',
      (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});

    await tester.pumpWidget(buildApp());
    await tester.pump();

    expect(find.text(l10n.appTitle), findsOneWidget);
    expect(find.text(l10n.appTagline), findsOneWidget);

    // Let the 8s initialization timeout fire and route away.
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
  });

  testWidgets('routes to home when onboarding_completed is true',
      (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});

    await tester.pumpWidget(buildApp());
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();

    expect(find.text('HOME_SCREEN'), findsOneWidget);
    expect(find.text('ONBOARDING_SCREEN'), findsNothing);
  });

  testWidgets('routes to onboarding when onboarding_completed is unset',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(buildApp());
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();

    expect(find.text('ONBOARDING_SCREEN'), findsOneWidget);
    expect(find.text('HOME_SCREEN'), findsNothing);
  });

  testWidgets('shows retry when DI is not ready, then routes after recovery',
      (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    final ready = Completer<String>();
    getIt.registerSingletonAsync<String>(() => ready.future);

    await tester.pumpWidget(buildApp());
    await tester.pump(const Duration(seconds: 8));
    await tester.pump();

    expect(find.text(l10n.retry), findsOneWidget);

    ready.complete('ready');
    await tester.pump();

    await tester.tap(find.text(l10n.retry));
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();

    expect(find.text('HOME_SCREEN'), findsOneWidget);
  });
}
