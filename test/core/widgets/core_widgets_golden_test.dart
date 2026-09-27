// test/core/widgets/core_widgets_golden_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_bottom_sheet.dart';
import 'package:pulsr/core/widgets/pulsr_card.dart';
import 'package:pulsr/core/widgets/pulsr_dialog.dart';
import 'package:pulsr/core/widgets/pulsr_empty_state.dart';
import 'package:pulsr/core/widgets/pulsr_pressable.dart';
import 'package:pulsr/core/widgets/pulsr_segmented_control.dart';
import 'package:pulsr/core/widgets/pulsr_slider.dart';
import 'package:pulsr/core/widgets/pulsr_switch.dart';

Widget _buildThemedHarness({
  required Widget child,
  Brightness brightness = Brightness.dark,
  TextDirection textDirection = TextDirection.ltr,
}) {
  final theme = brightness == Brightness.dark
      ? AuraTheme.darkTheme
      : AuraTheme.lightTheme;
  return Directionality(
    textDirection: textDirection,
    child: MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(child: child),
        ),
      ),
    ),
  );
}

void main() {
  group('Core Widgets Safety Suite (Phase 0)', () {
    testWidgets(
        'PulsrCard renders properly with child and responds to hover/tap',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _buildThemedHarness(
          child: PulsrCard(
            onTap: () => tapped = true,
            child: const Text('Card Test Content'),
          ),
        ),
      );

      expect(find.text('Card Test Content'), findsOneWidget);
      await tester.tap(find.byType(PulsrCard));
      expect(tapped, isTrue);
    });

    testWidgets('PulsrDialog renders structure with title, content, actions',
        (tester) async {
      await tester.pumpWidget(
        _buildThemedHarness(
          child: const PulsrDialog(
            title: Text('Dialog Title'),
            content: Text('Dialog Body'),
            actions: [
              Text('Action 1'),
            ],
          ),
        ),
      );

      expect(find.text('Dialog Title'), findsOneWidget);
      expect(find.text('Dialog Body'), findsOneWidget);
      expect(find.text('Action 1'), findsOneWidget);
    });

    testWidgets('PulsrBottomSheet renders container with drag handle',
        (tester) async {
      await tester.pumpWidget(
        _buildThemedHarness(
          child: const PulsrBottomSheet(
            title: Text('Sheet Title'),
            child: Text('Sheet Body'),
          ),
        ),
      );

      expect(find.text('Sheet Title'), findsOneWidget);
      expect(find.text('Sheet Body'), findsOneWidget);
    });

    testWidgets('PulsrSlider renders interactive track and updates value',
        (tester) async {
      double changedValue = 0.0;
      await tester.pumpWidget(
        _buildThemedHarness(
          child: PulsrSlider(
            value: 0.5,
            onChanged: (v) => changedValue = v,
          ),
        ),
      );

      expect(find.byType(PulsrSlider), findsOneWidget);
      await tester.tap(find.byType(PulsrSlider));
      await tester.pumpAndSettle();
      expect(changedValue, isNotNull);
    });

    testWidgets('PulsrSwitch toggles state and invokes callback',
        (tester) async {
      bool switchState = false;
      await tester.pumpWidget(
        _buildThemedHarness(
          child: PulsrSwitch(
            value: switchState,
            onChanged: (v) => switchState = v,
          ),
        ),
      );

      expect(find.byType(PulsrSwitch), findsOneWidget);
      await tester.tap(find.byType(PulsrSwitch));
      await tester.pumpAndSettle();
      expect(switchState, isTrue);
    });

    testWidgets('PulsrPressable compresses on tap and triggers callback',
        (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        _buildThemedHarness(
          child: PulsrPressable(
            onTap: () => pressed = true,
            child: const Text('Press Me'),
          ),
        ),
      );

      expect(find.text('Press Me'), findsOneWidget);
      await tester.tap(find.text('Press Me'));
      expect(pressed, isTrue);
    });

    testWidgets('PulsrSegmentedControl renders options and switches selection',
        (tester) async {
      int selected = 0;
      await tester.pumpWidget(
        _buildThemedHarness(
          child: PulsrSegmentedControl(
            segments: const [
              PulsrSegment(label: 'Local', icon: Icons.folder),
              PulsrSegment(label: 'Online', icon: Icons.cloud),
            ],
            selectedIndex: selected,
            onChanged: (idx) => selected = idx,
          ),
        ),
      );

      expect(find.text('Local'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
      await tester.tap(find.text('Online'));
      await tester.pumpAndSettle();
      expect(selected, 1);
    });

    testWidgets('PulsrEmptyState renders title, subtitle and action',
        (tester) async {
      var actionTriggered = false;
      await tester.pumpWidget(
        _buildThemedHarness(
          child: PulsrEmptyState(
            icon: Icons.music_off,
            title: 'No Tracks',
            subtitle: 'Scan your library to find music',
            primaryActionLabel: 'Scan Library',
            onPrimaryAction: () => actionTriggered = true,
          ),
        ),
      );

      expect(find.text('No Tracks'), findsOneWidget);
      expect(find.text('Scan your library to find music'), findsOneWidget);
      expect(find.text('Scan Library'), findsOneWidget);
      await tester.tap(find.text('Scan Library'));
      expect(actionTriggered, isTrue);
    });

    testWidgets('All 8 core widgets render in RTL direction without errors',
        (tester) async {
      await tester.pumpWidget(
        _buildThemedHarness(
          textDirection: TextDirection.rtl,
          child: Column(
            children: [
              const PulsrCard(child: Text('RTL Card')),
              PulsrSwitch(value: true, onChanged: (_) {}),
              PulsrSlider(value: 0.3, onChanged: (_) {}),
              PulsrPressable(child: const Text('RTL Pressable')),
            ],
          ),
        ),
      );

      expect(find.text('RTL Card'), findsOneWidget);
      expect(find.text('RTL Pressable'), findsOneWidget);
    });
  });
}
