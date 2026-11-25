// Covers the Battery saver switch in
// lib/features/settings/presentation/widgets/audio_output_section.dart: the
// preference round-trip and the fact that the stored value drives the switch.
import 'package:bloc_test/bloc_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/settings/presentation/widgets/audio_sound_section.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  // A wired route keeps the speaker-only battery-optimization card (which
  // probes Android services) out of the tree; the battery saver row is
  // device-independent, so it still renders below the branch.
  const state = SettingsState(
    currentOutputDevice: AudioOutputInfo(
      deviceName: 'Wired Headphones',
      isUsbDac: false,
      sampleRate: 48000,
      bitDepth: 24,
      isBitPerfectActive: false,
      activeDeviceType: 'wired',
    ),
  );

  Future<void> pumpSection(WidgetTester tester) async {
    final cubit = MockSettingsCubit();
    when(() => cubit.state).thenReturn(state);
    when(() => cubit.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());

    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<SettingsCubit>.value(
          value: cubit,
          child: Scaffold(
            body: SingleChildScrollView(
              child: DeviceAdaptiveOutputSection(state: state),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('battery saver is off by default and persists when enabled',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpSection(tester);

    expect(find.text(l10n.settingsBatterySaverTitle), findsOneWidget);
    expect(find.text(l10n.settingsBatterySaverDesc), findsOneWidget);

    await tester.ensureVisible(find.text(l10n.settingsBatterySaverTitle));
    await tester.tap(find.text(l10n.settingsBatterySaverTitle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PrefsKeys.batterySaverEnabled), isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('a stored preference drives the switch and can be turned off',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {PrefsKeys.batterySaverEnabled: true});
    await pumpSection(tester);

    // The restored value is on, so the next tap must turn it off; a switch
    // stuck at false would write true instead.
    await tester.ensureVisible(find.text(l10n.settingsBatterySaverTitle));
    await tester.tap(find.text(l10n.settingsBatterySaverTitle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PrefsKeys.batterySaverEnabled), isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
      'true low-power route is off by default and persists when enabled',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpSection(tester);

    expect(find.text('True Low-Power Route'), findsOneWidget);

    await tester.ensureVisible(find.text('True Low-Power Route'));
    await tester.tap(find.text('True Low-Power Route'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PrefsKeys.lowPowerRouteEnabled), isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
