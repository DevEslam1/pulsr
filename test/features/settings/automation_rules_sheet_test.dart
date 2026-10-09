// Covers lib/features/settings/presentation/widgets/automation_rules_sheet.dart:
// loading/empty/populated rendering, the enable toggle, the unsupported-trigger
// gate and the dismiss-to-delete + undo flow.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/automation_rules_service.dart';
import 'package:pulsr/core/services/settings_profiles_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_switch.dart';
import 'package:pulsr/features/settings/presentation/widgets/automation_rules_sheet.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockAutomationRulesService extends Mock
    implements AutomationRulesService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    getIt.registerSingleton<AutomationRulesService>(AutomationRulesService());
    getIt.registerSingleton<SettingsProfilesService>(SettingsProfilesService());
  });

  tearDown(() async {
    await getIt.reset();
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 1200);
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
        home: const Scaffold(body: AutomationRulesSheet()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('a load failure degrades to the empty state', (tester) async {
    await getIt.reset();
    final rules = MockAutomationRulesService();
    when(() => rules.getRules()).thenAnswer((_) async => throw Exception('x'));
    getIt.registerSingleton<AutomationRulesService>(rules);
    getIt.registerSingleton<SettingsProfilesService>(SettingsProfilesService());

    await pumpSheet(tester);

    expect(find.text(l10n.noAutomationRules), findsOneWidget);
  });

  testWidgets('showAutomationRulesSheet opens the sheet from a host',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAutomationRulesSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AutomationRulesSheet), findsOneWidget);
  });

  testWidgets('empty rule set shows the empty hint', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpSheet(tester);

    expect(find.text(l10n.automationRules), findsOneWidget);
    expect(find.text(l10n.noAutomationRules), findsOneWidget);
  });

  testWidgets('renders supported and unsupported rules with their profile name',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'setting_automation_rules': jsonEncode([
        {
          'id': 'r1',
          'trigger': 'bluetoothConnected',
          'targetProfileId': 'profile_custom_1',
          'enabled': true,
        },
        {
          'id': 'r2',
          'trigger': 'deviceCharging',
          'targetProfileId': 'profile_custom_1',
          'enabled': true,
        },
      ]),
      'setting_custom_profiles': jsonEncode([
        {
          'id': 'profile_custom_1',
          'name': 'My Custom',
          'type': 'custom',
        },
      ]),
    });
    await pumpSheet(tester);

    expect(find.text(AutomationTrigger.bluetoothConnected.label), findsOneWidget);
    expect(find.text(AutomationTrigger.deviceCharging.label), findsOneWidget);
    // Supported rule resolves its profile name; charging is not detectable.
    expect(find.text(l10n.settingsApplyProfileName('My Custom')), findsOneWidget);
    expect(find.text(l10n.settingsNotDetectable), findsOneWidget);
    expect(find.byType(PulsrSwitchListTile), findsNWidgets(2));
  });

  testWidgets('toggling a rule persists the new enabled value', (tester) async {
    SharedPreferences.setMockInitialValues({
      'setting_automation_rules': jsonEncode([
        {
          'id': 'r1',
          'trigger': 'headphonesPlugged',
          'targetProfileId': 'profile_custom_1',
          'enabled': true,
        },
      ]),
    });
    await pumpSheet(tester);

    await tester.tap(find.byType(PulsrSwitchListTile));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final rules = await AutomationRulesService().getRules();
    expect(rules.single.enabled, isFalse);
  });

  testWidgets('dismissing a rule deletes it and undo re-inserts it',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'setting_automation_rules': jsonEncode([
        {
          'id': 'r1',
          'trigger': 'bluetoothConnected',
          'targetProfileId': 'profile_custom_1',
          'enabled': true,
        },
      ]),
    });
    await pumpSheet(tester);

    await tester.drag(find.byType(Dismissible), const Offset(-700, 0));
    await tester.pumpAndSettle();

    expect(await AutomationRulesService().getRules(), isEmpty);
    expect(find.text(l10n.undo), findsOneWidget);

    await tester.tap(find.text(l10n.undo));
    await tester.pumpAndSettle();

    expect((await AutomationRulesService().getRules()).length, 1);
  });
}
