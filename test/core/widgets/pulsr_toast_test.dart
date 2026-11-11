import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_toast.dart';
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
        body: child,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    PulsrToast.hide();
  });

  group('PulsrToast Widget Tests', () {
    testWidgets('shows toast notification and auto-dismisses', (tester) async {
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () {
                PulsrToast.show(
                  context,
                  message: 'Track added to queue',
                  duration: const Duration(milliseconds: 500),
                );
              },
              child: const Text('Show Toast'),
            );
          },
        ),
      ));

      await tester.tap(find.text('Show Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Track added to queue'), findsOneWidget);

      // Advance past duration to auto-dismiss
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('Track added to queue'), findsNothing);
    });

    testWidgets('dedupe and refresh: identical message while active keeps single instance and refreshes timer',
        (tester) async {
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) {
            return Column(
              children: [
                ElevatedButton(
                  onPressed: () {
                    PulsrToast.show(
                      context,
                      message: 'Duplicate alert',
                      duration: const Duration(milliseconds: 1000),
                    );
                  },
                  child: const Text('Trigger 1'),
                ),
                ElevatedButton(
                  onPressed: () {
                    PulsrToast.show(
                      context,
                      message: 'Duplicate alert',
                      duration: const Duration(milliseconds: 1000),
                    );
                  },
                  child: const Text('Trigger 2'),
                ),
              ],
            );
          },
        ),
      ));

      // Trigger first toast
      await tester.tap(find.text('Trigger 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Duplicate alert'), findsOneWidget);

      // Advance 600ms (more than half the duration)
      await tester.pump(const Duration(milliseconds: 600));

      // Trigger identical second toast: dedupes and refreshes
      await tester.tap(find.text('Trigger 2'));
      await tester.pump();

      // Only ONE widget instance on screen
      expect(find.text('Duplicate alert'), findsOneWidget);

      // Advance another 600ms: total 1200ms from start, but refreshed timer has not expired yet!
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Duplicate alert'), findsOneWidget);

      // Finally advance past the refreshed duration
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('Duplicate alert'), findsNothing);
    });
  });
}
