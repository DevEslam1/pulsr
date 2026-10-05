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

  setUp(() {
    SoundFeedbackService.resetForTesting();
    SharedPreferences.setMockInitialValues({});
    _messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );

    scanner = MockMediaScannerService();
    when(() => scanner.requestPermission()).thenAnswer((_) async => true);
    when(() => scanner.scanDeviceLibrary()).thenAnswer((_) async => 0);

    settingsCubit = MockSettingsCubit();
    settingsController = StreamController<SettingsState>.broadcast();
    when(() => settingsCubit.state).thenReturn(const SettingsState());
    when(() => settingsCubit.stream)
        .thenAnswer((_) => settingsController.stream);
  });

  tearDown(() {
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
      {int frames = 2, Duration step = const Duration(milliseconds: 400)}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(step);
    }
  }

  testWidgets('renders the first page with skip and next affordances',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    expect(find.text('PULSR'), findsOneWidget);
    expect(find.text(l10n.skipAction), findsOneWidget);
    expect(find.text(l10n.next), findsOneWidget);
    expect(find.text(l10n.grantAccess), findsNothing);

    // Drain the infinite Pulsr logo animation before teardown.
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('tapping next advances to the final page CTA', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text(l10n.next));
      await tester.pump();
      await settleFrames(tester);
    }

    expect(find.text(l10n.grantAccess), findsOneWidget);
    expect(find.text(l10n.skipAction), findsNothing);
  });

  testWidgets('skip jumps straight to the final page', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    await tester.tap(find.text(l10n.skipAction));
    await tester.pump();
    await settleFrames(tester);

    expect(find.text(l10n.grantAccess), findsOneWidget);
    expect(find.text(l10n.skipAction), findsNothing);
  });

  testWidgets('grant access persists onboarding_completed and navigates home',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    await tester.tap(find.text(l10n.skipAction));
    await tester.pump();
    await settleFrames(tester);

    await tester.tap(find.text(l10n.grantAccess));
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
