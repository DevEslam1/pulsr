// Onboarding edge-flow coverage: the denied-permission dialog (limited vs.
// open-settings branches), the scan-failure snackbar, a hard permission
// exception, and the page-5 accent colour interaction. The happy path is
// already covered by onboarding_screen_test.dart.
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/sound_feedback_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/features/onboarding/presentation/onboarding_screen.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockMediaScannerService extends Mock implements MediaScannerService {}

class MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l10n = lookupAppLocalizations(const Locale('en'));

  late MockMediaScannerService scanner;
  late MockSettingsCubit settingsCubit;
  late StreamController<SettingsState> settingsController;

  setUpAll(() {
    registerFallbackValue(const Color(0xFF000000));
  });

  setUp(() {
    SoundFeedbackService.resetForTesting();
    SharedPreferences.setMockInitialValues({});
    _messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    _messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (call) async => true,
    );

    scanner = MockMediaScannerService();
    when(() => scanner.requestPermission()).thenAnswer((_) async => true);
    when(() => scanner.scanDeviceLibrary()).thenAnswer((_) async => 0);

    settingsCubit = MockSettingsCubit();
    settingsController = StreamController<SettingsState>.broadcast();
    when(() => settingsCubit.state).thenReturn(const SettingsState());
    when(() => settingsCubit.stream)
        .thenAnswer((_) => settingsController.stream);
    when(() => settingsCubit.setCustomAccentColor(any()))
        .thenAnswer((_) async {});
  });

  tearDown(() {
    settingsController.close();
    _messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    _messenger.setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'), null);
  });

  Widget buildApp() {
    final router = GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: Text('HOME_SCREEN')),
        ),
        GoRoute(
          path: '/onboarding',
          builder: (context, state) => OnboardingScreen(scannerService: scanner),
        ),
      ],
    );

    return BlocProvider<SettingsCubit>.value(
      value: settingsCubit,
      child: MaterialApp.router(
        theme: AuraTheme.darkTheme,
        routerConfig: router,
      ),
    );
  }

  Future<void> goToFinalPage(WidgetTester tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.tap(find.text(l10n.skipAction));
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  testWidgets('denied storage access -> limited access completes onboarding',
      (tester) async {
    when(() => scanner.requestPermission()).thenAnswer((_) async => false);
    await goToFinalPage(tester);

    await tester.tap(find.text(l10n.grantAccess));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Denied dialog is shown with both affordances.
    expect(find.text(l10n.audioAccessRequired), findsOneWidget);
    expect(find.text(l10n.continueLimitedAccess), findsOneWidget);
    expect(find.text(l10n.openSettings), findsOneWidget);

    await tester.tap(find.text(l10n.continueLimitedAccess));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(find.text('HOME_SCREEN'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding_completed'), isTrue);
    // The library is never scanned when access was denied.
    verifyNever(() => scanner.scanDeviceLibrary());
  });

  testWidgets('denied storage access -> open settings keeps the user in place',
      (tester) async {
    when(() => scanner.requestPermission()).thenAnswer((_) async => false);
    await goToFinalPage(tester);

    await tester.tap(find.text(l10n.grantAccess));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text(l10n.openSettings));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Still on onboarding: the settings branch returns without completing.
    expect(find.text('HOME_SCREEN'), findsNothing);
    expect(find.text(l10n.grantAccess), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding_completed'), isNull);
  });

  testWidgets('a library scan failure still completes onboarding',
      (tester) async {
    when(() => scanner.scanDeviceLibrary())
        .thenAnswer((_) async => throw Exception('scan boom'));
    await goToFinalPage(tester);

    await tester.tap(find.text(l10n.grantAccess));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    // The failure is caught and logged, then onboarding still completes.
    expect(tester.takeException(), isNull);
    expect(find.text('HOME_SCREEN'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding_completed'), isTrue);
    verify(() => scanner.scanDeviceLibrary()).called(1);
  });

  testWidgets('a permission request throw surfaces the generic error snackbar',
      (tester) async {
    when(() => scanner.requestPermission())
        .thenAnswer((_) async => throw Exception('permission boom'));
    await goToFinalPage(tester);

    await tester.tap(find.text(l10n.grantAccess));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.text(l10n.somethingWentWrong), findsOneWidget);
    // The screen stays put after a hard failure.
    expect(find.text('HOME_SCREEN'), findsNothing);
  });

  testWidgets('page 5 lets the user pick a custom accent colour',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.tap(find.text(l10n.skipAction));
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    // The accent swatches are rendered on the final page.
    final swatches = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label != null &&
          w.properties.label!.startsWith(l10n.customAccentColor),
    );
    expect(swatches, findsWidgets);

    await tester.tap(swatches.first);
    await tester.pump();
    verify(() => settingsCubit.setCustomAccentColor(any())).called(1);
  });
}
