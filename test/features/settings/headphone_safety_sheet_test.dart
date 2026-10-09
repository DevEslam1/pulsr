// Covers lib/features/settings/presentation/widgets/headphone_safety_sheet.dart
//
// Drives the WHO sound-dose gauge against a stubbed AudioEffectsChannel:
// loading -> dose states (optimal / high / limiter active), the safety toggle,
// and the reset-dose confirmation flow.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/audio/audio_effects_channel.dart';
import 'package:pulsr/features/settings/presentation/widgets/headphone_safety_sheet.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  double dose = 0.3;
  bool attenuation = false;
  bool safetyApplied = true;
  int resetCalls = 0;
  final calls = <String>[];

  setUp(() {
    dose = 0.3;
    attenuation = false;
    safetyApplied = true;
    resetCalls = 0;
    calls.clear();
    AudioEffectsChannel().dispose();

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.audioEffects),
      (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'getWeeklyDose':
            return dose;
          case 'isSafetyAttenuationActive':
            return attenuation;
          case 'resetWeeklyDose':
            resetCalls++;
            return true;
          case 'setHeadphoneSafetyParams':
            return safetyApplied;
        }
        return true;
      },
    );
  });

  tearDown(() {
    AudioEffectsChannel().dispose();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.audioEffects), null);
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
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
        home: const Scaffold(body: HeadphoneSafetySheet()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> disposeSheet(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('renders the header and the refreshed weekly dose',
      (tester) async {
    await pumpSheet(tester);

    expect(find.text(l10n.headphoneSafetyTitle), findsOneWidget);
    expect(find.text(l10n.weeklySoundAllowance), findsOneWidget);
    expect(find.text('30.0%'), findsOneWidget);
    expect(find.text(l10n.optimalExposureDesc), findsOneWidget);
    expect(calls, contains('getWeeklyDose'));

    await disposeSheet(tester);
  });

  testWidgets('shows the high-dose warning between 80% and 100%',
      (tester) async {
    dose = 0.9;
    await pumpSheet(tester);

    expect(find.text('90.0%'), findsOneWidget);
    expect(find.text(l10n.highSoundDoseWarning), findsOneWidget);
    expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);

    await disposeSheet(tester);
  });

  testWidgets('shows the limiter-active message when attenuation engages',
      (tester) async {
    dose = 1.2;
    attenuation = true;
    await pumpSheet(tester);

    expect(find.text(l10n.safetyLimiterActiveDesc), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

    await disposeSheet(tester);
  });

  testWidgets('telemetry polling refreshes the displayed dose',
      (tester) async {
    await pumpSheet(tester);
    expect(find.text('30.0%'), findsOneWidget);

    dose = 0.5;
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(find.text('50.0%'), findsOneWidget);

    await disposeSheet(tester);
  });

  testWidgets('toggling the safety switch calls the native setter',
      (tester) async {
    await pumpSheet(tester);

    final switchTile = find.byType(SwitchListTile);
    expect(tester.widget<SwitchListTile>(switchTile).value, isTrue);

    await tester.tap(switchTile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(calls, contains('setHeadphoneSafetyParams'));
    expect(tester.widget<SwitchListTile>(switchTile).value, isFalse);

    await disposeSheet(tester);
  });

  testWidgets('a rejected native safety toggle is logged and left unchanged',
      (tester) async {
    safetyApplied = false;
    await pumpSheet(tester);

    final switchTile = find.byType(SwitchListTile);
    await tester.tap(switchTile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The setter rethrows, so the switch keeps its previous value.
    expect(tester.widget<SwitchListTile>(switchTile).value, isTrue);

    await disposeSheet(tester);
  });

  testWidgets('confirming the reset dialog resets the dose and shows a snackbar',
      (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.text(l10n.resetDoseAction));
    await tester.pumpAndSettle();

    expect(find.text(l10n.resetWeeklyDoseTitle), findsOneWidget);

    await tester.tap(find.descendant(
      of: find.byType(Dialog),
      matching: find.text(l10n.resetDoseAction),
    ));
    await tester.pumpAndSettle();

    expect(resetCalls, 1);
    expect(find.text(l10n.weeklyDoseResetSnackbar), findsOneWidget);

    await disposeSheet(tester);
  });

  testWidgets('cancelling the reset dialog does not reset the dose',
      (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.text(l10n.resetDoseAction));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
      of: find.byType(Dialog),
      matching: find.text(l10n.cancel),
    ));
    await tester.pumpAndSettle();

    expect(resetCalls, 0);

    await disposeSheet(tester);
  });
}
