// Covers lib/features/settings/presentation/widgets/audio_setup_wizard.dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/settings/presentation/widgets/audio_setup_wizard.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  late MockSettingsCubit cubit;

  void stubApplyMethods() {
    when(() => cubit.applyMaximumQualityPreset()).thenAnswer((_) async {});
    when(() => cubit.applySmoothPlaybackPreset()).thenAnswer((_) async {});
    when(() => cubit.applyPoorNetworkPreset()).thenAnswer((_) async {});
    when(() => cubit.setBitPerfectOutput(any())).thenAnswer((_) async {});
    when(() => cubit.setFollowTrackSampleRate(any())).thenAnswer((_) async {});
    when(() => cubit.setCrossfade(any())).thenAnswer((_) async {});
    when(() => cubit.setGapless(any())).thenAnswer((_) async {});
  }

  Future<void> pumpWizard(
    WidgetTester tester, {
    AudioOutputInfo? device,
  }) async {
    cubit = MockSettingsCubit();
    when(() => cubit.state)
        .thenReturn(SettingsState(currentOutputDevice: device));
    when(() => cubit.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
    stubApplyMethods();

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
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AudioSetupWizardSheet(cubit: cubit),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tapNext(WidgetTester tester) async {
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('step 1 shows all output types and defaults to speaker',
      (tester) async {
    await pumpWizard(tester);

    expect(find.text(l10n.settingsWizardTitle), findsOneWidget);
    expect(find.text(l10n.settingsWizardStep1Title), findsOneWidget);
    expect(find.text('USB DAC / Dongle'), findsOneWidget);
    expect(find.text('Bluetooth Audio'), findsOneWidget);
    expect(find.text('Speaker / Built-in'), findsOneWidget);
    expect(find.text('Wired Headphones'), findsOneWidget);
  });

  testWidgets('back button appears after advancing and steps backwards',
      (tester) async {
    await pumpWizard(tester);
    await tapNext(tester);
    expect(find.text(l10n.settingsWizardStep2Title), findsOneWidget);
    expect(find.text(l10n.cancel), findsOneWidget);

    await tester.tap(find.text(l10n.cancel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l10n.settingsWizardStep1Title), findsOneWidget);
  });

  testWidgets('fidelity + USB DAC applies quality preset and follow-track',
      (tester) async {
    await pumpWizard(
      tester,
      device: const AudioOutputInfo(
        deviceName: 'USB DAC',
        isUsbDac: true,
        sampleRate: 96000,
        bitDepth: 24,
        isBitPerfectActive: false,
      ),
    );
    await tapNext(tester);
    await tester.tap(find.text(l10n.settingsWizardFidelity));
    await tester.pump();
    await tapNext(tester);
    expect(find.text(l10n.settingsWizardStep3Title), findsOneWidget);

    await tester.tap(find.text(l10n.settingsWizardApply));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    verify(() => cubit.applyMaximumQualityPreset()).called(1);
    verify(() => cubit.setFollowTrackSampleRate(true)).called(1);
    verify(() => cubit.setCrossfade(0.0)).called(1);
    verify(() => cubit.setGapless(true)).called(1);
  });

  testWidgets('bluetooth + save-data applies poor-network preset',
      (tester) async {
    await pumpWizard(
      tester,
      device: const AudioOutputInfo(
        deviceName: 'Buds',
        isUsbDac: false,
        sampleRate: 48000,
        bitDepth: 16,
        isBluetooth: true,
        isBitPerfectActive: false,
      ),
    );
    await tapNext(tester);
    await tester.tap(find.text(l10n.settingsWizardDataSaver));
    await tester.pump();
    await tapNext(tester);

    await tester.tap(find.text(l10n.settingsWizardApply));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    verify(() => cubit.applyPoorNetworkPreset()).called(1);
    verify(() => cubit.setBitPerfectOutput(false)).called(1);
  });

  testWidgets('crossfade transition wires gapless off and 3s crossfade',
      (tester) async {
    await pumpWizard(tester);
    await tapNext(tester);
    await tester.tap(find.text(l10n.settingsWizardBalanced));
    await tester.pump();
    await tapNext(tester);
    await tester.tap(find.text(l10n.crossfade));
    await tester.pump();

    await tester.tap(find.text(l10n.settingsWizardApply));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    verify(() => cubit.applySmoothPlaybackPreset()).called(1);
    verify(() => cubit.setGapless(false)).called(1);
    verify(() => cubit.setCrossfade(3.0)).called(1);
  });

  testWidgets('none transition disables gapless and zeroes crossfade',
      (tester) async {
    await pumpWizard(tester);
    await tapNext(tester);
    await tapNext(tester);
    await tester.tap(find.text(l10n.rgOff));
    await tester.pump();

    await tester.tap(find.text(l10n.settingsWizardApply));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    verify(() => cubit.setGapless(false)).called(1);
    verify(() => cubit.setCrossfade(0.0)).called(1);
  });

  testWidgets('close icon pop dismisses the wizard', (tester) async {
    await pumpWizard(tester);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget);
    expect(find.text(l10n.settingsWizardTitle), findsNothing);
  });

  testWidgets('failure while applying resets the busy flag and keeps the sheet',
      (tester) async {
    await pumpWizard(tester);
    await tapNext(tester);
    await tapNext(tester);
    when(() => cubit.applySmoothPlaybackPreset())
        .thenAnswer((_) async => throw StateError('boom'));

    await tester.tap(find.text(l10n.settingsWizardApply));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Still on the wizard (no pop) and no stuck spinner.
    expect(find.text(l10n.settingsWizardTitle), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(l10n.settingsWizardApply), findsOneWidget);
  });
}
