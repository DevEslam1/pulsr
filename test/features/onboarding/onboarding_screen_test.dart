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
  late StreamController<ScanProgressUpdate> progressController;

  setUpAll(() {
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

    scanner = MockMediaScannerService();
    progressController = StreamController<ScanProgressUpdate>.broadcast();
    when(() => scanner.requestPermission()).thenAnswer((_) async => true);
    when(() => scanner.scanDeviceLibrary()).thenAnswer((_) async => 42);
    when(() => scanner.detailedProgress)
        .thenAnswer((_) => progressController.stream);

    settingsCubit = MockSettingsCubit();
    settingsController = StreamController<SettingsState>.broadcast();
    when(() => settingsCubit.state).thenReturn(const SettingsState());
    when(() => settingsCubit.stream)
        .thenAnswer((_) => settingsController.stream);
    when(() => settingsCubit.setExperienceMode(any()))
        .thenAnswer((_) async {});
    when(() => settingsCubit.setPlayerThemeMode(any()))
        .thenAnswer((_) async {});
  });

  tearDown(() {
    progressController.close();
    settingsController.close();
    _messenger.setMockMethodCallHandler(SystemChannels.platform, null);
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

  Future<void> settleFrames(WidgetTester tester,
      {int frames = 2,
      Duration step = const Duration(milliseconds: 400)}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(step);
    }
  }

  testWidgets(
      'renders Step 1 with skip, next, permissions card, and live track counter',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    expect(find.text('PULSR'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text(l10n.skipAction), findsOneWidget);
    expect(find.text(l10n.next), findsOneWidget);
    expect(find.text(l10n.grantAccess), findsOneWidget);
    expect(find.text(l10n.lastScanTracks(0)), findsOneWidget);
    expect(find.text('Start Listening'), findsNothing);

    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('Step 1 grant access updates live scanned track counter inline',
      (tester) async {
    when(() => scanner.scanDeviceLibrary()).thenAnswer((_) async {
      progressController.add(const ScanProgressUpdate(
        progress: 0.5,
        scannedCount: 18,
        totalCount: 42,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return 42;
    });

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await settleFrames(tester);

    await tester.tap(find.text(l10n.grantAccess));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text(l10n.lastScanTracks(18)), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text(l10n.lastScanTracks(42)), findsOneWidget);
    expect(find.text('HOME_SCREEN'), findsNothing);
    verify(() => scanner.requestPermission()).called(1);
    verify(() => scanner.scanDeviceLibrary()).called(1);
  });

  testWidgets('tapping next twice advances through 3 steps to final CTA',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    // Step 1 -> Step 2
    await tester.tap(find.text(l10n.next));
    await tester.pump();
    await settleFrames(tester);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text(l10n.experienceModeTitle), findsOneWidget);

    // Step 2 -> Step 3
    await tester.tap(find.text(l10n.next));
    await tester.pump();
    await settleFrames(tester);

    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('Start Listening'), findsOneWidget);
    expect(find.text(l10n.settingsSetUpSound), findsOneWidget);
    expect(find.text(l10n.skipAction), findsNothing);
  });

  testWidgets('skip jumps straight to Step 3 final page', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    await tester.tap(find.text(l10n.skipAction));
    await tester.pump();
    await settleFrames(tester);

    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('Start Listening'), findsOneWidget);
    expect(find.text(l10n.skipAction), findsNothing);
  });

  testWidgets(
      'Start Listening requests permission, scans, persists onboarding_completed, and navigates home',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    await tester.tap(find.text(l10n.skipAction));
    await tester.pump();
    await settleFrames(tester);

    await tester.tap(find.text('Start Listening'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await settleFrames(tester, frames: 2);

    expect(find.text('HOME_SCREEN'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding_completed'), isTrue);

    verify(() => scanner.requestPermission()).called(1);
    verify(() => scanner.scanDeviceLibrary()).called(1);
  });
}
