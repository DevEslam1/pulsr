// Regression test for P1-2.4: one tool that fails to initialize must disable
// only its own row (with an inline error) and leave every other row usable.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/extras/presentation/extras_screen.dart';
import 'package:pulsr/features/extras/presentation/extras_strings.dart';
import 'package:pulsr/features/settings/presentation/widgets/settings_tiles.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SettingsNavTile rowFor(WidgetTester tester, String title) {
    return tester.widget<SettingsNavTile>(
      find.ancestor(
        of: find.text(title),
        matching: find.byType(SettingsNavTile),
      ),
    );
  }

  testWidgets('a failed tool disables only its own row', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(MaterialApp(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ExtrasScreen(
        debugToolErrors: <ExtrasTool, String>{
          ExtrasTool.usb: 'USB ergonomics could not start',
        },
      ),
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text(ExtrasStrings.usbTitle),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // The failed row shows its inline error and has no action.
    expect(find.text('USB ergonomics could not start'), findsOneWidget);
    expect(rowFor(tester, ExtrasStrings.usbTitle).onTap, isNull);

    // Every other row keeps its normal subtitle: the failure is not global.
    final profilesRow = rowFor(tester, ExtrasStrings.profilesTitle);
    expect(profilesRow.subtitle, ExtrasStrings.profilesSubtitle);
    expect(
      find.text('USB ergonomics could not start'),
      findsOneWidget,
      reason: 'the error must stay on its own row',
    );
  });

  testWidgets('a throwing init is caught and siblings stay navigable',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // The USB tool reads the exclusive-service status and subscribes to its
    // event channel. Widget tests report TargetPlatform.android, so the
    // channel is activated for real; mock it or the missing plugin fails the
    // test from outside the app code.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.pulsr.music/usb_exclusive'),
            (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.pulsr.music/usb_exclusive_events'),
            (call) async => null);

    await tester.pumpWidget(MaterialApp(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Make the real _initProfiles throw so the per-tool try/catch runs.
      home: const ExtrasScreen(
        debugFailInits: <ExtrasTool>{ExtrasTool.profiles},
      ),
    ));

    // _load() awaits real service initialization (prefs, platform-message
    // futures), which pumpAndSettle does not track: give it real time until the
    // hub replaces its loading indicator with the list.
    for (var i = 0; i < 200 && find.byType(ListView).evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(find.byType(ListView), findsOneWidget,
        reason: 'the hub must leave the loading state');
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text(ExtrasStrings.profilesTitle),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final profiles = rowFor(tester, ExtrasStrings.profilesTitle);
    expect(profiles.subtitle, ExtrasStrings.toolUnavailable,
        reason: 'the caught failure is named on its own row');
    expect(profiles.onTap, isNull);

    // Diagnostics initialized on its own and remains usable.
    final diagnostics = rowFor(tester, ExtrasStrings.diagnosticsTitle);
    expect(diagnostics.subtitle, ExtrasStrings.diagnosticsSubtitle);
    expect(diagnostics.onTap, isNotNull,
        reason: 'one failed tool must not blank the hub');
  });
}
