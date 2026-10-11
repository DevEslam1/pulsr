// test/core/widgets/pulsr_bottom_sheet_modal_test.dart
//
// Non-root sheets must register with PulsrModalTracker manually: the root
// observer cannot see a nested navigator, so without the manual push/pop the
// mini-player dock stayed over the sheet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_bottom_sheet.dart';
import 'package:pulsr/core/widgets/pulsr_modal_tracker.dart';

Widget _host({required bool useRootNavigator}) {
  return MaterialApp(
    theme: AuraTheme.darkTheme,
    home: Navigator(
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => PulsrSheetHelper.showPulsrSheet<void>(
                  context: context,
                  useRootNavigator: useRootNavigator,
                  builder: (_) => const SizedBox(
                    height: 220,
                    child: Center(child: Text('Nested sheet')),
                  ),
                ),
                child: const Text('Open sheet'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  tearDown(() {
    while (PulsrModalTracker.isModalOpen.value) {
      PulsrModalTracker.pop();
    }
  });

  testWidgets('non-root sheets register and unregister in the modal tracker',
      (tester) async {
    await tester.pumpWidget(_host(useRootNavigator: false));
    expect(PulsrModalTracker.isModalOpen.value, isFalse);

    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Nested sheet'), findsOneWidget);
    expect(PulsrModalTracker.isModalOpen.value, isTrue);

    // Barrier tap dismisses the sheet and releases the tracker.
    await tester.tapAt(const Offset(12, 12));
    await tester.pumpAndSettle();

    expect(find.text('Nested sheet'), findsNothing);
    expect(PulsrModalTracker.isModalOpen.value, isFalse);
  });

  testWidgets(
      'root sheets are left to the navigator observer (no double count)',
      (tester) async {
    await tester.pumpWidget(_host(useRootNavigator: true));

    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
    expect(find.text('Nested sheet'), findsOneWidget);

    // No root PulsrModalObserver is installed here, so the tracker stays
    // untouched — proof the helper did not push manually for the root case.
    expect(PulsrModalTracker.isModalOpen.value, isFalse);

    Navigator.of(tester.element(find.text('Nested sheet')), rootNavigator: true)
        .pop();
    await tester.pumpAndSettle();
  });
}
