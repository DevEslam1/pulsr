// Regression test for P1-2.4: one tool that fails to initialize must disable
// only its own row (with an inline error) and leave every other row usable.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/extras/presentation/extras_screen.dart';
import 'package:pulsr/features/settings/presentation/widgets/settings_tiles.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:pulsr/l10n/generated/app_localizations_en.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = AppLocalizationsEn();

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
      find.text(l10n.extrasUsbTitle),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // The failed row shows its inline error and has no main tile action.
    expect(find.text('USB ergonomics could not start'), findsOneWidget);
    expect(rowFor(tester, l10n.extrasUsbTitle).onTap, isNull);

    // Every other row keeps its normal subtitle: the failure is not global.
    final profilesRow = rowFor(tester, l10n.extrasProfilesTitle);
    expect(profilesRow.subtitle, l10n.extrasProfilesSubtitle);
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
      find.text(l10n.extrasProfilesTitle),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final profiles = rowFor(tester, l10n.extrasProfilesTitle);
    expect(profiles.subtitle, l10n.extrasToolUnavailable,
        reason: 'the caught failure is named on its own row');
    expect(profiles.onTap, isNull);

    // Diagnostics initialized on its own and remains usable.
    final diagnostics = rowFor(tester, l10n.extrasDiagnosticsTitle);
    expect(diagnostics.subtitle, l10n.extrasDiagnosticsSubtitle);
    expect(diagnostics.onTap, isNotNull,
        reason: 'one failed tool must not blank the hub');
  });
}
