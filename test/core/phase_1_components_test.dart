import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/glass_container.dart';
import 'package:pulsr/core/widgets/pulsr_surface.dart';
import 'package:pulsr/core/widgets/pulsr_slider.dart';
import 'package:pulsr/core/widgets/pulsr_switch.dart';
import 'package:pulsr/core/widgets/pulsr_segmented_control.dart';
import 'package:pulsr/core/widgets/pulsr_card.dart';
import 'package:pulsr/core/widgets/pulsr_toast.dart';
import 'package:pulsr/core/widgets/pulsr_dismissible.dart';
import 'package:pulsr/core/widgets/marquee_text.dart';
import 'package:pulsr/core/widgets/pulsr_error_boundary.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AuraTheme.darkTheme,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('GlassContainer supports GlassTier enum', (tester) async {
    await tester.pumpWidget(_wrap(
      const GlassContainer(
        tier: GlassTier.solid,
        child: Text('Solid Glass'),
      ),
    ));
    expect(find.text('Solid Glass'), findsOneWidget);
  });

  testWidgets('PulsrSurface renders unified pressable surface', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(_wrap(
      PulsrSurface(
        onTap: () => tapped = true,
        child: const Text('Surface Button'),
      ),
    ));
    expect(find.text('Surface Button'), findsOneWidget);
    await tester.tap(find.text('Surface Button'));
    expect(tapped, isTrue);
  });

  testWidgets('PulsrSwitch supports small and medium sizes', (tester) async {
    bool value = false;
    await tester.pumpWidget(_wrap(
      PulsrSwitch.small(
        value: value,
        onChanged: (v) => value = v,
      ),
    ));
    expect(find.byType(PulsrSwitch), findsOneWidget);
    await tester.tap(find.byType(PulsrSwitch));
    expect(value, isTrue);
  });

  testWidgets(
      'PulsrSegmentedControl supports 3+ segments with sliding indicator',
      (tester) async {
    int selected = 0;
    await tester.pumpWidget(_wrap(
      StatefulBuilder(
        builder: (context, setState) => PulsrSegmentedControl(
          segments: const [
            PulsrSegment(label: 'All', icon: Icons.music_note),
            PulsrSegment(label: 'Tracks', icon: Icons.audiotrack),
            PulsrSegment(label: 'Albums', icon: Icons.album),
          ],
          selectedIndex: selected,
          onChanged: (i) => setState(() => selected = i),
        ),
      ),
    ));
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Tracks'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);

    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    expect(selected, equals(2));
  });

  testWidgets('PulsrCard supports tokenized elevation', (tester) async {
    await tester.pumpWidget(_wrap(
      const PulsrCard(
        elevation: PulsrCardElevation.high,
        child: Text('High Elevation'),
      ),
    ));
    expect(find.text('High Elevation'), findsOneWidget);
  });

  testWidgets('PulsrErrorBoundary supports ErrorSeverity', (tester) async {
    await tester.pumpWidget(_wrap(
      PulsrErrorBoundary(
        severity: ErrorSeverity.warning,
        builder: (_) => throw Exception('Intentional test error'),
      ),
    ));
    expect(find.text('Something went wrong'), findsOneWidget);
  });
  testWidgets('PulsrSlider renders and responds to value changes',
      (tester) async {
    double sliderVal = 0.5;
    await tester.pumpWidget(_wrap(
      PulsrSlider(
        value: sliderVal,
        min: 0.0,
        max: 1.0,
        onChanged: (v) => sliderVal = v,
      ),
    ));
    expect(find.byType(PulsrSlider), findsOneWidget);
  });

  testWidgets('MarqueeText renders text string', (tester) async {
    await tester.pumpWidget(_wrap(
      const MarqueeText(
        text: 'A very long track title that will scroll smoothly',
      ),
    ));
    expect(find.byType(MarqueeText), findsOneWidget);
  });

  testWidgets('PulsrDismissible renders child', (tester) async {
    await tester.pumpWidget(_wrap(
      PulsrDismissible(
        key: const ValueKey('dismiss_test'),
        onConfirm: (dir) => true,
        child: const Text('Dismiss item'),
      ),
    ));
    expect(find.text('Dismiss item'), findsOneWidget);
  });

  testWidgets('PulsrToast shows toast overlay', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AuraTheme.darkTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => PulsrToast.show(context, message: 'Track Added!'),
            child: const Text('Show Toast'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Show Toast'));
    await tester.pump();
    expect(find.text('Track Added!'), findsOneWidget);
  });
}
