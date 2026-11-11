import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_dismissible.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 80,
            child: child,
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PulsrDismissible Widget Tests', () {
    testWidgets('first swipe snaps to middle confirm state, and timeout resets to zero',
        (tester) async {
      bool confirmed = false;

      await tester.pumpWidget(_wrap(
        PulsrDismissible(
          confirmTimeout: const Duration(milliseconds: 1000),
          background: const Text('DELETE_ACTION'),
          secondaryBackground: const Text('SECONDARY_ACTION'),
          onConfirm: (dir) {
            confirmed = true;
            return true;
          },
          child: const ListTile(title: Text('Swipe Me')),
        ),
      ));

      expect(find.text('Swipe Me'), findsOneWidget);

      // Swipe right past defaultThreshold (60%)
      await tester.drag(find.text('Swipe Me'), const Offset(260, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Should be in middle confirm state; not confirmed yet
      expect(confirmed, isFalse);

      // Wait for confirm timeout (1000ms) to elapse
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump(const Duration(milliseconds: 300));

      // Did not confirm; reset back to closed state
      expect(confirmed, isFalse);
    });

    testWidgets('two-stage confirmation triggers onConfirm on second swipe',
        (tester) async {
      bool confirmed = false;

      await tester.pumpWidget(_wrap(
        PulsrDismissible(
          confirmTimeout: const Duration(seconds: 3),
          background: const Text('DELETE_ACTION'),
          secondaryBackground: const Text('SECONDARY_ACTION'),
          onConfirm: (dir) {
            confirmed = true;
            return true;
          },
          child: const ListTile(title: Text('Two Stage')),
        ),
      ));

      // 1. First swipe: snaps to middle
      await tester.drag(find.text('Two Stage'), const Offset(260, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(confirmed, isFalse);

      // 2. Second swipe in same direction: confirms action
      await tester.drag(find.text('Two Stage'), const Offset(260, 0),
          warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(confirmed, isTrue);
    });
  });
}
