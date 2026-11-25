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
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/theme_registry.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/settings/presentation/widgets/audio_setup_wizard.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockMediaScannerService extends Mock implements MediaScannerService {}

class MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

class MockPlayerCubit extends MockCubit<PlayerState> implements PlayerCubit {}

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  late MockMediaScannerService scanner;
  late MockSettingsCubit settingsCubit;
  late MockPlayerCubit playerCubit;
  late StreamController<SettingsState> settingsController;
  late StreamController<ScanProgressUpdate> progressController;

  setUpAll(() {
    registerFallbackValue(ExperienceMode.normal);
    registerFallbackValue(PlayerThemeMode.clean);
    registerFallbackValue(const Color(0xFF000000));
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
    when(() => scanner.scanDeviceLibrary()).thenAnswer((_) async => 128);
    when(() => scanner.detailedProgress)
        .thenAnswer((_) => progressController.stream);

    settingsCubit = MockSettingsCubit();
    settingsController = StreamController<SettingsState>.broadcast();
    when(() => settingsCubit.state).thenReturn(const SettingsState());
    when(() => settingsCubit.stream)
        .thenAnswer((_) => settingsController.stream);
    when(() => settingsCubit.setExperienceMode(any())).thenAnswer((_) async {});
    when(() => settingsCubit.setPlayerThemeMode(any()))
        .thenAnswer((_) async {});
    when(() => settingsCubit.setCustomAccentColor(any()))
        .thenAnswer((_) async {});

    playerCubit = MockPlayerCubit();
    when(() => playerCubit.state).thenReturn(const PlayerState());
    when(() => playerCubit.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
  });

  tearDown(() {
    progressController.close();
    settingsController.close();
    _messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget buildApp({
    bool reduceMotion = false,
    double textScale = 1.0,
    bool includePlayerCubit = false,
  }) {
    when(() => settingsCubit.state).thenReturn(
      SettingsState(reduceMotion: reduceMotion),
    );
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
          builder: (context, state) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduceMotion,
              textScaler: TextScaler.linear(textScale),
            ),
            child: OnboardingScreen(scannerService: scanner),
          ),
        ),
      ],
    );

    return MultiBlocProvider(
      providers: [
        BlocProvider<SettingsCubit>.value(value: settingsCubit),
        if (includePlayerCubit)
          BlocProvider<PlayerCubit>.value(value: playerCubit),
      ],
      child: MaterialApp.router(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
  }

  testWidgets(
      'reduced motion snaps across all 3 onboarding steps immediately without animation delay',
      (tester) async {
    await tester.pumpWidget(buildApp(reduceMotion: true));
    await tester.pump();

    expect(find.text('1 / 3'), findsOneWidget);

    // Next -> Step 2 in a single pump (no multi-frame animation settle required)
    await tester.tap(find.text(l10n.next));
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text(l10n.experienceModeTitle), findsOneWidget);

    // Next -> Step 3 in a single pump
    await tester.tap(find.text(l10n.next));
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('Start Listening'), findsOneWidget);

    // Previous -> Step 2 in a single pump
    await tester.tap(find.byTooltip(l10n.previous));
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);

    // Skip -> Step 3 in a single pump
    await tester.tap(find.text(l10n.skipAction));
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);
  });

  testWidgets(
      'Step 2 renders live ThemeRegistry.preview thumbnails when PlayerCubit is available',
      (tester) async {
    await tester.pumpWidget(
      buildApp(reduceMotion: true, includePlayerCubit: true),
    );
    await tester.pump();

    await tester.tap(find.text(l10n.next));
    await tester.pump();

    // All 4 top themes render with PlayerThemePreviewHost (isPreview: true)
    expect(find.byType(PlayerThemePreviewHost), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Step 3 launches 1-tap AudioSetupWizardSheet and completes via Start Listening',
      (tester) async {
    await tester.pumpWidget(buildApp(reduceMotion: true));
    await tester.pump();

    await tester.tap(find.text(l10n.skipAction));
    await tester.pump();

    // Tap the 1-tap AudioSetupWizard launch card
    await tester.tap(find.byKey(const ValueKey('onboarding_audio_wizard_btn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AudioSetupWizardSheet), findsOneWidget);

    // Dismiss the wizard sheet
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AudioSetupWizardSheet), findsNothing);

    // Tap Start Listening
    await tester.tap(find.text('Start Listening'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('HOME_SCREEN'), findsOneWidget);
  });

  for (final scale in <double>[1.3, 1.6]) {
    testWidgets(
        '3-step OnboardingScreen renders with zero overflow at ${scale}x text scale',
        (tester) async {
      tester.view.physicalSize = const Size(400, 840);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildApp(reduceMotion: true, textScale: scale),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Step 2 at large text scale
      await tester.tap(find.text(l10n.next));
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Step 3 at large text scale
      await tester.tap(find.text(l10n.next));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
