// test/features/shell/shortcut_help_sheet_test.dart
//
// Widget coverage for the desktop/tablet keyboard-shortcut reference sheet:
// every shortcut row renders its key/description/icon, and the static [show]
// helper opens it in a modal route above the hosting navigator.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/shell/presentation/widgets/shortcut_help_sheet.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

Widget host(Widget child) => MaterialApp(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders the title, subtitle and every shortcut row',
      (tester) async {
    // Tall surface so all 12 lazily-built list rows are laid out at once.
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const ShortcutHelpSheet()));
    await tester.pumpAndSettle();

    expect(find.text('Keyboard Shortcuts'), findsOneWidget);
    expect(find.text('Desktop and tablet quick navigation keys'), findsOneWidget);

    // One row per binding: 12 keys.
    for (final key in ['Space', '→', '←', '↑', '↓', 'N', 'P', 'F', 'M', 'L', 'Q', '?']) {
      expect(find.text(key), findsOneWidget, reason: 'missing key $key');
    }

    expect(find.text('Play / Pause'), findsOneWidget);
    expect(find.text('Toggle Queue'), findsOneWidget);
    expect(find.text('Shortcuts Guide'), findsOneWidget);
    expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
  });

  testWidgets('static show mounts the sheet above the current route',
      (tester) async {
    await tester.pumpWidget(host(Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => ShortcutHelpSheet.show(context),
        child: const Text('open-shortcuts'),
      ),
    )));
    await tester.pumpAndSettle();

    expect(find.byType(ShortcutHelpSheet), findsNothing);

    await tester.tap(find.text('open-shortcuts'));
    await tester.pumpAndSettle();

    expect(find.byType(ShortcutHelpSheet), findsOneWidget);
    expect(find.text('Keyboard Shortcuts'), findsOneWidget);

    // Dismiss the modal so no timers/routes survive the test.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byType(ShortcutHelpSheet), findsNothing);
  });
}