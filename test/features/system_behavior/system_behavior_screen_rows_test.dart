// The fade slider and the volume curve/step rows are only shown once delivery
// is live (P0-1.7). The volume-rocker row stays hidden until a native key
// supplier exists, so it must NOT appear.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/system_behavior/system_behavior_screen.dart';
import 'package:pulsr/features/system_behavior/system_behavior_settings.dart';
import 'package:pulsr/features/system_behavior/system_behavior_strings.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SystemBehaviorSettings> pumpScreen(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SystemBehaviorSettings settings = SystemBehaviorSettings();
    await settings.load();
    await tester.pumpWidget(MaterialApp(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SystemBehaviorScreen(settings: settings),
    ));
    await tester.pumpAndSettle();
    return settings;
  }

  testWidgets('fade, curve and step rows are exposed', (tester) async {
    await pumpScreen(tester);

    expect(
        find.text(SystemBehaviorStrings.fadeOutOnPauseMsTitle), findsOneWidget);

    // The list is taller than the 600 px test surface; scroll each row in.
    await tester.scrollUntilVisible(
      find.text(SystemBehaviorStrings.volumeStepPercentTitle),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(SystemBehaviorStrings.softwareVolumeCurveTitle),
        findsOneWidget);
    expect(find.text(SystemBehaviorStrings.volumeStepPercentTitle),
        findsOneWidget);
  });

  testWidgets('volume-rocker row stays hidden without a native key supplier',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text(SystemBehaviorStrings.volumeRockerTrackSwitchTitle),
        findsNothing,
        reason: 'no KEYCODE_VOLUME_* supplier forwards the keys yet');
  });

  testWidgets('choosing the logarithmic curve persists it', (tester) async {
    final settings = await pumpScreen(tester);

    await tester
        .ensureVisible(find.text(SystemBehaviorStrings.curveLogarithmic));
    await tester.pumpAndSettle();
    await tester.tap(find.text(SystemBehaviorStrings.curveLogarithmic));
    await tester.pumpAndSettle();

    expect(settings.softwareVolumeCurve, SoftwareVolumeCurve.logarithmic);
  });
}
