import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/shimmer_skeleton.dart';
import 'package:pulsr/features/auth/cubit/auth_cubit.dart';
import 'package:pulsr/features/auth/cubit/auth_state.dart';
import 'package:pulsr/features/auth/presentation/auth_sheet.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/settings/presentation/widgets/audio_setup_wizard.dart';
import 'package:pulsr/features/settings/presentation/widgets/settings_hero_card.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

class MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  late MockSettingsCubit settingsCubit;
  late MockAuthCubit authCubit;

  setUpAll(() {
    registerFallbackValue(ExperienceMode.normal);
    registerFallbackValue(AppThemeMode.dark);
    registerFallbackValue(ReplayGainMode.off);
  });

  setUp(() {
    settingsCubit = MockSettingsCubit();
    when(() => settingsCubit.state).thenReturn(const SettingsState());
    when(() => settingsCubit.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
    when(() => settingsCubit.setExperienceMode(any())).thenAnswer((_) async {});
    when(() => settingsCubit.setThemeMode(any())).thenAnswer((_) async {});
    when(() => settingsCubit.setOfflineOnlyMode(any()))
        .thenAnswer((_) async {});
    when(() => settingsCubit.setStrictBitPerfect(any()))
        .thenAnswer((_) async {});
    when(() => settingsCubit.setBitPerfectOutput(any()))
        .thenAnswer((_) async {});
    when(() => settingsCubit.setAaudioOutputEnabled(any()))
        .thenAnswer((_) async {});
    when(() => settingsCubit.setDvcEnabled(any())).thenAnswer((_) async {});
    when(() => settingsCubit.setFloatOutputEnabled(any()))
        .thenAnswer((_) async {});
    when(() => settingsCubit.setFollowTrackSampleRate(any()))
        .thenAnswer((_) async {});
    when(() => settingsCubit.setOutputFormatNegotiationEnabled(any()))
        .thenAnswer((_) async {});
    when(() => settingsCubit.setBluetoothHiResEnabled(any()))
        .thenAnswer((_) async {});
    when(() => settingsCubit.setReplayGainMode(any())).thenAnswer((_) async {});
    when(() => settingsCubit.setCrossfade(any())).thenAnswer((_) async {});
    when(() => settingsCubit.setGapless(any())).thenAnswer((_) async {});

    authCubit = MockAuthCubit();
    when(() => authCubit.state).thenReturn(const AuthState());
    when(() => authCubit.stream)
        .thenAnswer((_) => const Stream<AuthState>.empty());
  });

  testWidgets(
      'SettingsQuickControlsStrip toggles Experience Mode, Theme/AMOLED, Offline-Only Mode, and opens Audio Engine/EQ',
      (tester) async {
    var audioOpened = false;

    await tester.pumpWidget(
      BlocProvider<SettingsCubit>.value(
        value: settingsCubit,
        child: MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SettingsQuickControlsStrip(
              onOpenAudioEngine: () => audioOpened = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Quick Controls'), findsOneWidget);

    // 1. Experience Mode tile (>= 48x48dp)
    final expTile = find.byKey(const ValueKey('quick_control_experience_mode'));
    expect(expTile, findsOneWidget);
    expect(tester.getSize(expTile).height, greaterThanOrEqualTo(48));
    await tester.tap(expTile);
    await tester.pump();
    verify(() => settingsCubit.setExperienceMode(ExperienceMode.professional))
        .called(1);

    // 2. Theme / AMOLED tile (>= 48x48dp)
    final themeTile = find.byKey(const ValueKey('quick_control_theme_amoled'));
    expect(themeTile, findsOneWidget);
    expect(tester.getSize(themeTile).height, greaterThanOrEqualTo(48));
    await tester.tap(themeTile);
    await tester.pump();
    verify(() => settingsCubit.setThemeMode(AppThemeMode.amoled)).called(1);

    // 3. Offline-Only Mode tile (>= 48x48dp)
    final offlineTile =
        find.byKey(const ValueKey('quick_control_offline_only'));
    expect(offlineTile, findsOneWidget);
    expect(tester.getSize(offlineTile).height, greaterThanOrEqualTo(48));
    await tester.tap(offlineTile);
    await tester.pump();
    verify(() => settingsCubit.setOfflineOnlyMode(true)).called(1);

    // 4. Active Audio Engine / EQ tile (>= 48x48dp)
    final audioTile =
        find.byKey(const ValueKey('quick_control_audio_engine_eq'));
    expect(audioTile, findsOneWidget);
    expect(tester.getSize(audioTile).height, greaterThanOrEqualTo(48));
    await tester.tap(audioTile);
    await tester.pump();
    expect(audioOpened, isTrue);
  });

  testWidgets(
      'ResetAudioEngineGuardrailCard resets audio engine to recommended defaults',
      (tester) async {
    await tester.pumpWidget(
      BlocProvider<SettingsCubit>.value(
        value: settingsCubit,
        child: MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: ResetAudioEngineGuardrailCard(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Reset Audio Engine to Recommended'), findsOneWidget);
    final btn =
        find.byKey(const ValueKey('reset_audio_engine_recommended_btn'));
    expect(tester.getSize(btn).height, greaterThanOrEqualTo(48));

    await tester.tap(btn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    verify(() => settingsCubit.setStrictBitPerfect(false)).called(1);
    verify(() => settingsCubit.setBitPerfectOutput(false)).called(1);
    verify(() => settingsCubit.setAaudioOutputEnabled(false)).called(1);
    verify(() => settingsCubit.setDvcEnabled(false)).called(1);
    verify(() => settingsCubit.setFloatOutputEnabled(true)).called(1);
    verify(() => settingsCubit.setFollowTrackSampleRate(true)).called(1);
    verify(() => settingsCubit.setOutputFormatNegotiationEnabled(true))
        .called(1);
    verify(() => settingsCubit.setBluetoothHiResEnabled(true)).called(1);
    verify(() => settingsCubit.setReplayGainMode(ReplayGainMode.off)).called(1);
    verify(() => settingsCubit.setCrossfade(0.0)).called(1);
    verify(() => settingsCubit.setGapless(true)).called(1);
    expect(
      find.text(l10n.presetAppliedMessage(l10n.settingsWizardBalanced)),
      findsOneWidget,
    );
  });

  for (final scale in <double>[1.3, 1.6]) {
    testWidgets(
        'SettingsQuickControlsStrip, ResetAudioEngineGuardrailCard, AudioSetupWizardSheet, and AuthSheet render with zero overflow at ${scale}x text scale',
        (tester) async {
      tester.view.physicalSize = const Size(380, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<SettingsCubit>.value(value: settingsCubit),
            BlocProvider<AuthCubit>.value(value: authCubit),
          ],
          child: MaterialApp(
            theme: AuraTheme.darkTheme,
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    const SettingsQuickControlsStrip(),
                    const ResetAudioEngineGuardrailCard(),
                    AudioSetupWizardSheet(cubit: settingsCubit),
                    const AuthSheet(),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('SkeletonBox renders cleanly under reduced motion',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SkeletonShimmer(
              child: SkeletonBox(width: 120, height: 48, radius: 12),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(SkeletonBox), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
