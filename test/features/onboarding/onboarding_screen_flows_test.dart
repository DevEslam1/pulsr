// Onboarding edge-flow coverage: the denied-permission dialog (limited vs.
// open-settings branches), the scan-failure snackbar, a hard permission
// exception, and Step 2 Experience Mode / Player Theme / accent colour
// interactions.
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
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
    registerFallbackValue(ExperienceMode.normal);
    registerFallbackValue(PlayerThemeMode.clean);
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
    when(() => scanner.detailedProgress)
        .thenAnswer((_) => const Stream<ScanProgressUpdate>.empty());

    settingsCubit = MockSettingsCubit();
    settingsController = StreamController<SettingsState>.broadcast();
    when(() => settingsCubit.state).thenReturn(const SettingsState());
    when(() => settingsCubit.stream)
        .thenAnswer((_) => settingsController.stream);
    when(() => settingsCubit.setCustomAccentColor(any()))
        .thenAnswer((_) async {});
    when(() => settingsCubit.setExperienceMode(any()))
        .thenAnswer((_) async {});
    when(() => settingsCubit.setPlayerThemeMode(any()))
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
          builder: (context, state) =>
              OnboardingScreen(scannerService: scanner),
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

    await tester.tap(find.text('Start Listening'));
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

    await tester.tap(find.text('Start Listening'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text(l10n.openSettings));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Still on onboarding: the settings branch returns without completing.
    expect(find.text('HOME_SCREEN'), findsNothing);
    expect(find.text('Start Listening'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding_completed'), isNull);
  });

  testWidgets(
      'dismissing the denied dialog via the barrier keeps onboarding open',
      (tester) async {
    when(() => scanner.requestPermission()).thenAnswer((_) async => false);
    await goToFinalPage(tester);

    await tester.tap(find.text('Start Listening'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text(l10n.audioAccessRequired), findsOneWidget);

    // Tap the barrier (outside the dialog) to dismiss without choosing.
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(l10n.audioAccessRequired), findsNothing);
    expect(find.text('HOME_SCREEN'), findsNothing);
    expect(find.text('Start Listening'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding_completed'), isNull);
    verifyNever(() => scanner.scanDeviceLibrary());
  });

  testWidgets('a library scan failure still completes onboarding',
      (tester) async {
    when(() => scanner.scanDeviceLibrary())
        .thenAnswer((_) async => throw Exception('scan boom'));
    await goToFinalPage(tester);

    await tester.tap(find.text('Start Listening'));
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

    await tester.tap(find.text('Start Listening'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.text(l10n.somethingWentWrong), findsOneWidget);
    // The screen stays put after a hard failure.
    expect(find.text('HOME_SCREEN'), findsNothing);
  });

  testWidgets(
      'Step 2 lets the user switch Experience Mode, pick top 4 Player Themes, and pick a custom accent colour',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.tap(find.text(l10n.next));
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    // 1. Switch Experience Mode to Professional
    await tester.tap(find.text(l10n.experienceModeProfessional));
    await tester.pump();
    verify(() => settingsCubit.setExperienceMode(ExperienceMode.professional))
        .called(1);

    // 2. Select one of the top 4 Player Themes (Vinyl Turntable)
    final vinylFinder = find.text(l10n.settingsThemeVinylTurntable);
    await tester.ensureVisible(vinylFinder);
    await tester.pump();
    await tester.tap(vinylFinder);
    await tester.pump();
    verify(() => settingsCubit.setPlayerThemeMode(PlayerThemeMode.vinyl))
        .called(1);

    // 3. Pick a custom accent colour swatch
    final swatches = find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          w.properties.label != null &&
          w.properties.label!.startsWith(l10n.customAccentColor),
    );
    expect(swatches, findsWidgets);
    await tester.ensureVisible(swatches.first);
    await tester.pump();
    await tester.tap(swatches.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    verify(() => settingsCubit.setCustomAccentColor(any())).called(1);
  });
}
