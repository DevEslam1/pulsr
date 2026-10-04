import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';
import 'package:pulsr/core/widgets/pulsr_dock_tracker.dart';
import 'package:pulsr/core/widgets/pulsr_pressable.dart';
import 'package:pulsr/core/widgets/pulsr_switch.dart';
import 'package:pulsr/core/widgets/pulsr_segmented_control.dart';
import 'package:pulsr/core/widgets/marquee_text.dart';

Widget host(Widget child,
        {TextDirection direction = TextDirection.ltr,
        bool reducedMotion = false}) =>
    MaterialApp(
      theme: AuraTheme.darkTheme,
      home: MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: Directionality(
              textDirection: direction,
              child: Scaffold(body: Center(child: child)))),
    );

void main() {
  testWidgets('pressable supports Enter and Space once per activation',
      (tester) async {
    var presses = 0;
    await tester.pumpWidget(host(PulsrPressable(
        onTap: () => presses++,
        child: const SizedBox(width: 100, height: 48, child: Text('Action')))));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(presses, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(presses, 2);
  });

  for (final direction in TextDirection.values) {
    testWidgets(
        'small switch has 48dp hit area and correct thumb direction $direction',
        (tester) async {
      await tester.pumpWidget(host(
          PulsrSwitch.small(value: true, onChanged: (_) {}),
          direction: direction));
      final size = tester.getSize(find.byType(PulsrSwitch));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      final thumb = tester.widget<Transform>(find
          .descendant(
              of: find.byType(PulsrSwitch), matching: find.byType(Transform))
          .first);
      expect(thumb.transform.entry(0, 3),
          direction == TextDirection.rtl ? lessThan(0) : greaterThan(0));
    });

    testWidgets('selected segment aligns with its indicator $direction',
        (tester) async {
      await tester.pumpWidget(host(
          SizedBox(
              width: 400,
              child: PulsrSegmentedControl(segments: const [
                PulsrSegment(label: 'First', icon: Icons.music_note),
                PulsrSegment(label: 'Second', icon: Icons.public)
              ], selectedIndex: 0, onChanged: (_) {})),
          direction: direction));
      final indicator = find.byType(AnimatedPositionedDirectional);
      final selected = find.text('First');
      expect(
          (tester.getCenter(indicator).dx - tester.getCenter(selected).dx)
              .abs(),
          lessThan(25));
      expect(tester.getSize(find.byType(PulsrPressable).first).height,
          greaterThanOrEqualTo(48));
    });
  }

  testWidgets('dock reserve updates live and disappears on standalone routes',
      (tester) async {
    double? reserve;
    final content = Builder(builder: (context) {
      reserve = PulsrLayoutMetrics.scrollBottom(context);
      return const SizedBox();
    });
    PulsrDockTracker.dockHeight.value = 64;
    addTearDown(() => PulsrDockTracker.dockHeight.value = 0);
    await tester.pumpWidget(host(PulsrDockAware(child: content)));
    expect(reserve, 88);
    PulsrDockTracker.dockHeight.value = 148;
    await tester.pump();
    expect(reserve, 172);
    await tester.pumpWidget(host(content));
    expect(reserve, 24);
  });

  testWidgets(
      'reduced motion replaces scrolling marquee with a static accessible label',
      (tester) async {
    const text =
        'A very long track title that cannot fit inside its narrow container';
    final marquee = SizedBox(
        width: 80,
        child: MarqueeText(text: text, pauseDuration: Duration.zero));
    await tester.pumpWidget(host(marquee));
    await tester.pump();
    expect(
        find.descendant(
            of: find.byType(MarqueeText),
            matching: find.byType(SingleChildScrollView)),
        findsOneWidget);
    await tester.pumpWidget(host(marquee, reducedMotion: true));
    await tester.pump(const Duration(seconds: 3));
    expect(
        find.descendant(
            of: find.byType(MarqueeText),
            matching: find.byType(SingleChildScrollView)),
        findsNothing);
    expect(find.byTooltip(text), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('secondary and tertiary text maintain readable contrast on app surfaces',
      () {
    for (final theme in [
      AuraTheme.lightTheme,
      AuraTheme.darkTheme,
      AuraTheme.amoledTheme
    ]) {
      final p = theme.extension<PulsrPalette>()!;
      for (final text in [p.textSecondary, p.textTertiary]) {
        for (final surface in [p.surface, p.surfaceCard, p.surfaceContainer]) {
          final a = text.computeLuminance();
          final b = surface.computeLuminance();
          final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
          expect(ratio, greaterThanOrEqualTo(4.5), reason: '$text on $surface');
        }
      }
    }
  });
}
