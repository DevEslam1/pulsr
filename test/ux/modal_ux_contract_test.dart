// test/ux/modal_ux_contract_test.dart
//
// Locks the shared modal/touch-target contract:
// - adaptive sheets honor their max width and lift above the IME
// - compact buttons keep a 48dp interactive target even when visually smaller
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_adaptive_sheet.dart';
import 'package:pulsr/core/widgets/pulsr_button.dart';
import 'package:pulsr/core/widgets/pulsr_chip.dart';
import 'package:pulsr/core/widgets/pulsr_icon_button.dart';

Widget _host() {
  return MaterialApp(
    theme: AuraTheme.darkTheme,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => PulsrAdaptiveSheet.show<void>(
              context: context,
              maxWidth: 320,
              maxHeight: 500,
              builder: (_) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  Text('Sheet body'),
                  SizedBox(key: Key('sheet-tail'), height: 8),
                ],
              ),
            ),
            child: const Text('Open sheet'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('adaptive sheet honors max width and keyboard insets',
      (tester) async {
    tester.view.physicalSize = const Size(700, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(_host());
    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();

    final tail = find.byKey(const Key('sheet-tail'));
    expect(tail, findsOneWidget);
    final width = tester.getSize(tail).width;
    expect(width, lessThanOrEqualTo(320));
    expect(width, greaterThan(300));

    // The sheet starts at the bottom of the 1200dp viewport.
    expect(tester.getBottomRight(tail).dy, greaterThan(1150));

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    // 300dp keyboard leaves the sheet anchored above 900dp.
    expect(tester.getBottomRight(tail).dy, lessThanOrEqualTo(902));
  });

  testWidgets('compact buttons and chips keep a 48dp interactive target',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PulsrButton(
                  label: 'Small',
                  size: PulsrButtonSize.sm,
                  onPressed: () {},
                ),
                PulsrButton(
                  label: 'Medium',
                  size: PulsrButtonSize.md,
                  onPressed: () {},
                ),
                PulsrIconButton(
                  icon: Icons.close_rounded,
                  onPressed: () {},
                ),
                PulsrChip(label: 'Filter', onTap: () {}),
              ],
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(PulsrButton).at(0)).height,
      greaterThanOrEqualTo(48.0),
    );
    expect(
      tester.getSize(find.byType(PulsrButton).at(1)).height,
      greaterThanOrEqualTo(48.0),
    );
    expect(
      tester.getSize(find.byType(PulsrIconButton)).height,
      greaterThanOrEqualTo(48.0),
    );
    expect(
      tester.getSize(find.byType(PulsrChip)).height,
      greaterThanOrEqualTo(48.0),
    );
  });
}
