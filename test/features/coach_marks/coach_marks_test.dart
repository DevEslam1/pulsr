import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/services/coach_mark_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/settings/presentation/widgets/settings_picker_sheets.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'package:pulsr/l10n/app_localizations_delegates.dart';

Widget _buildHarness(Widget child) {
  return MaterialApp(
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData.dark().copyWith(
      extensions: [AuraTheme.defaultDark],
    ),
    home: Scaffold(
      body: Center(child: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CoachMarkService.resetSession();
  });

  group('P6 Discoverability — Coach Marks Tests', () {
    testWidgets('First-encounter coach mark displays and persists key',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      CoachMarkService.resetSession();
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildHarness(
          Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => CoachMarkService.maybeShowDspExplainer(
                  context,
                  customPrefs: prefs,
                ),
                child: const Text('Open DSP'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open DSP'));
      await tester.pumpAndSettle();

      // Coach mark should be visible with Got it button
      expect(find.text('Got it'), findsOneWidget);
      expect(prefs.getBool(PrefsKeys.coachMarkDspSeen), isTrue);

      // Dismiss dialog
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();

      expect(find.text('Got it'), findsNothing);
    });

    testWidgets('Max one coach mark per session constraint is enforced',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      CoachMarkService.resetSession();
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildHarness(
          Builder(
            builder: (context) {
              return Column(
                children: [
                  ElevatedButton(
                    onPressed: () => CoachMarkService.maybeShowDspExplainer(
                      context,
                      customPrefs: prefs,
                    ),
                    child: const Text('First Mark'),
                  ),
                  ElevatedButton(
                    onPressed: () => CoachMarkService.maybeShowUsbDacExplainer(
                      context,
                      customPrefs: prefs,
                    ),
                    child: const Text('Second Mark'),
                  ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fire first coach mark
      await tester.tap(find.text('First Mark'));
      await tester.pumpAndSettle();
      expect(find.text('Got it'), findsOneWidget);

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();

      // Try firing second coach mark in the same session
      await tester.tap(find.text('Second Mark'));
      await tester.pumpAndSettle();

      // Must be suppressed because session already showed one
      expect(find.text('Got it'), findsNothing);
      expect(prefs.getBool(PrefsKeys.coachMarkUsbDacSeen), isNull);
    });

    testWidgets('Already-seen coach mark is suppressed even in fresh session',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.coachMarkDspSeen: true,
      });
      CoachMarkService.resetSession();
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildHarness(
          Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => CoachMarkService.maybeShowDspExplainer(
                  context,
                  customPrefs: prefs,
                ),
                child: const Text('Trigger'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trigger'));
      await tester.pumpAndSettle();

      expect(find.text('Got It'), findsNothing);
    });
  });

  group('P6 Discoverability — Version-Gated Whats New Sheet Tests', () {
    testWidgets(
        'Whats new sheet shows on new version and records last seen version',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildHarness(
          Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => maybeShowVersionGatedWhatsNew(
                  context,
                  customPrefs: prefs,
                ),
                child: const Text('Check Whats New'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Check Whats New'));
      await tester.pumpAndSettle();

      expect(find.text("What's New in Pulsr"), findsOneWidget);
      expect(prefs.getString(PrefsKeys.lastSeenAppVersion), isNotNull);

      // Dismiss
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Second check with same version is suppressed
      await tester.tap(find.text('Check Whats New'));
      await tester.pumpAndSettle();
      expect(find.text("What's New in Pulsr"), findsNothing);
    });
  });
}
