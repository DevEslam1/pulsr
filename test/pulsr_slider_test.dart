import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_slider.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AuraTheme.darkTheme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 48,
            child: child,
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PulsrSlider Widget Tests', () {
    testWidgets('renders wavy slider and triggers onChanged on drag',
        (tester) async {
      double currentVal = 0.5;
      bool endTriggered = false;

      await tester.pumpWidget(_wrap(
        StatefulBuilder(
          builder: (context, setState) {
            return PulsrSlider(
              value: currentVal,
              isWavy: true,
              animateWave: true,
              onChanged: (v) {
                setState(() => currentVal = v);
              },
              onChangeEnd: (v) {
                endTriggered = true;
              },
            );
          },
        ),
      ));

      expect(find.byType(PulsrSlider), findsOneWidget);

      // Drag slider
      await tester.drag(find.byType(PulsrSlider), const Offset(50, 0));
      await tester.pump();

      expect(currentVal, greaterThan(0.5));

      // Release gesture
      await tester.pumpAndSettle();
      expect(endTriggered, isTrue);
    });

    testWidgets('renders straight slider when isWavy is false', (tester) async {
      double currentVal = 0.2;

      await tester.pumpWidget(_wrap(
        PulsrSlider(
          value: currentVal,
          isWavy: false,
          onChanged: (v) => currentVal = v,
        ),
      ));

      expect(find.byType(PulsrSlider), findsOneWidget);
    });

    testWidgets('respects min and max bounds', (tester) async {
      double currentVal = 50.0;

      await tester.pumpWidget(_wrap(
        StatefulBuilder(
          builder: (context, setState) {
            return PulsrSlider(
              value: currentVal,
              min: 10.0,
              max: 100.0,
              isWavy: true,
              onChanged: (v) => setState(() => currentVal = v),
            );
          },
        ),
      ));

      // Drag far left
      await tester.drag(find.byType(PulsrSlider), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(currentVal, closeTo(10.0, 0.01));

      // Drag far right
      await tester.drag(find.byType(PulsrSlider), const Offset(500, 0));
      await tester.pumpAndSettle();
      expect(currentVal, closeTo(100.0, 0.01));
    });
  });
}
