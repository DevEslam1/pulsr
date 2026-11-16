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
    await tester.tapAt(const Offset(400, 50));
    await tester.pumpAndSettle();

    expect(find.text('Nested sheet'), findsNothing);
    expect(PulsrModalTracker.isModalOpen.value, isFalse);
  });

  testWidgets('phone portrait tap above sheet dismisses sheet', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var buttonPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => PulsrSheetHelper.showPulsrSheet<void>(
                  context: context,
                  builder: (_) => Container(
                    height: 250,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Text('Sheet Header'),
                        ElevatedButton(
                          onPressed: () => buttonPressed = true,
                          child: const Text('Action Button'),
                        ),
                      ],
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Sheet Header'), findsOneWidget);

    // 1. Tapping action button inside sheet triggers button and DOES NOT dismiss
    await tester.tap(find.text('Action Button'));
    await tester.pumpAndSettle();
    expect(buttonPressed, isTrue);
    expect(find.text('Sheet Header'), findsOneWidget);

    // 2. Tapping sheet background inside sheet DOES NOT dismiss
    final sheetCenter = tester.getCenter(find.text('Sheet Header'));
    await tester.tapAt(sheetCenter + const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(find.text('Sheet Header'), findsOneWidget);

    // 3. Tapping the empty space above the sheet dismisses the sheet
    await tester.tapAt(const Offset(200, 100));
    await tester.pumpAndSettle();
    expect(find.text('Sheet Header'), findsNothing);
  });

  testWidgets('isDismissible: false prevents tap-above dismissal', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => PulsrSheetHelper.showPulsrSheet<void>(
                  context: context,
                  isDismissible: false,
                  builder: (_) => const SizedBox(
                    height: 200,
                    child: Text('Non-dismissible sheet'),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Non-dismissible sheet'), findsOneWidget);

    // Tap on empty space above sheet: should NOT dismiss
    await tester.tapAt(const Offset(200, 100));
    await tester.pumpAndSettle();
    expect(find.text('Non-dismissible sheet'), findsOneWidget);
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
