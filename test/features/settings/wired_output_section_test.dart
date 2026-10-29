// Covers the wired / 3.5mm branch in
// lib/features/settings/presentation/widgets/audio_output_section.dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/settings/presentation/widgets/audio_sound_section.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  testWidgets('wired route exposes direct and float paths, not USB bit-perfect',
      (tester) async {
    final cubit = MockSettingsCubit();
    const state = SettingsState(
      currentOutputDevice: AudioOutputInfo(
        deviceName: 'Wired Headphones',
        isUsbDac: false,
        sampleRate: 48000,
        bitDepth: 24,
        isBitPerfectActive: false,
        activeDeviceType: 'wired',
      ),
      floatOutputEnabled: true,
    );
    when(() => cubit.state).thenReturn(state);
    when(() => cubit.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());

    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
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

    expect(find.text(l10n.settingsAaudioDirect), findsOneWidget);
    expect(find.text(l10n.settingsFloatDspPath), findsOneWidget);
    expect(find.text(l10n.equalizerAndSoundEffects), findsOneWidget);
    expect(find.text(l10n.settingsBitPerfectUsb), findsNothing);

    // AAudio Direct is off, so its buffer control stays hidden.
    expect(find.text(l10n.settingsAaudioBufferSize), findsNothing);
  });
}
