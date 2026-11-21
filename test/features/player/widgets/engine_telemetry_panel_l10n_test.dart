// test/features/player/widgets/engine_telemetry_panel_l10n_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/presentation/widgets/engine_telemetry_panel.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.audioEffects),
      (call) async {
        if (call.method == 'getDspBatteryEstimate') {
          return <String, dynamic>{
            'estimatedMahPerHour': 0.0,
            'lowPowerBypassActive': false,
            'activeStageCount': 0,
            'stageBreakdown': <String, double>{},
            'stagePowerSpecs': <String, double>{},
          };
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.audioEffects),
      null,
    );
  });

  Widget buildPanel(Locale locale) {
    return MaterialApp(
      locale: locale,
      theme: AuraTheme.darkTheme,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: SingleChildScrollView(
          child: EngineTelemetryPanel(initialExpanded: true),
        ),
      ),
    );
  }

  testWidgets('EngineTelemetryPanel renders localized strings in en, ar, es',
      (tester) async {
    await tester.pumpWidget(buildPanel(const Locale('en')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('DSP Power Consumption'), findsOneWidget);
    expect(find.text('All DSP stages idle (~0.0 mAh/h).'), findsOneWidget);
    expect(find.text('Low'), findsOneWidget);
    expect(find.text('B1'), findsOneWidget);

    await tester.pumpWidget(buildPanel(const Locale('ar')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('استهلاك طاقة DSP'), findsOneWidget);
    expect(find.text('جميع مراحل DSP خاملة (~0.0 مللي أمبير/ساعة).'),
        findsOneWidget);
    expect(find.text('منخفض'), findsOneWidget);

    await tester.pumpWidget(buildPanel(const Locale('es')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Consumo de energía DSP'), findsOneWidget);
    expect(
        find.text('Todas las etapas DSP inactivas (~0.0 mAh/h).'), findsOneWidget);
    expect(find.text('Graves'), findsOneWidget);
  });
}
