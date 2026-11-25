// test/features/player/eq_curve_visualizer_test.dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/headphone_target_curve.dart';
import 'package:pulsr/features/player/presentation/widgets/eq_curve_visualizer.dart';

void main() {
  group('EqCurveVisualizer Tests', () {
    testWidgets('renders flat response curve without crashing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 80,
                child: EqCurveVisualizer(
                  gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
                  activeColor: Colors.cyan,
                  height: 80,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(EqCurveVisualizer), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('renders Catmull-Rom curve with FFT spectrum overlay',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 80,
                child: EqCurveVisualizer(
                  gains: [3.0, 1.5, -2.0, -1.0, 0.0, 2.5, 4.0, 1.0, -3.0, 0.5],
                  activeColor: Colors.deepPurple,
                  height: 80,
                  spectrumData: [0.2, 0.4, 0.8, 0.6, 0.3, 0.1],
                  showGrid: true,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(EqCurveVisualizer), findsOneWidget);
    });

    testWidgets('invokes onGainChanged and onBandSelected on drag gesture',
        (tester) async {
      int? selectedBand;
      double? updatedGain;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 100,
                child: EqCurveVisualizer(
                  gains: const [0, 0, 0, 0, 0],
                  activeColor: Colors.amber,
                  height: 100,
                  onBandSelected: (band) {
                    selectedBand = band;
                  },
                  onGainChanged: (band, gain) {
                    updatedGain = gain;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      // Drag in the middle (band 2) upward (positive gain)
      final center = tester.getCenter(find.byType(EqCurveVisualizer));
      final gesture = await tester.startGesture(center);
      await tester.pump();

      // Pan upward by 25 pixels
      await gesture.moveBy(const Offset(0, -25));
      await tester.pump();

      expect(selectedBand, isNotNull);
      expect(selectedBand, equals(2));
      expect(updatedGain, isNotNull);
      expect(updatedGain!, greaterThan(0.0));

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('resets band gain to 0 dB on double tap', (tester) async {
      int? resetBand;
      double? resetGain;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 100,
                child: EqCurveVisualizer(
                  gains: const [4.0, 3.0, 2.0, 1.0, 0.0],
                  activeColor: Colors.amber,
                  height: 100,
                  onBandSelected: (band) {
                    resetBand = band;
                  },
                  onGainChanged: (band, gain) {
                    resetGain = gain;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      // Double tap on middle band (band 2)
      final center = tester.getCenter(find.byType(EqCurveVisualizer));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 400));

      expect(resetBand, equals(2));
      expect(resetGain, equals(0.0));
    });

    testWidgets('target-curve selector switches the dashed reference curve',
        (tester) async {
      HeadphoneTargetCurve? selected;
      var gainChanges = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 120,
                child: EqCurveVisualizer(
                  gains: const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
                  activeColor: Colors.cyan,
                  height: 120,
                  targetCurve: HeadphoneTargetCurve.harmanInEar2019,
                  onTargetCurveChanged: (curve) => selected = curve,
                  onGainChanged: (_, __) => gainChanges++,
                ),
              ),
            ),
          ),
        ),
      );

      // Renders the selected target and paints the chart without exceptions.
      expect(
          find.text(HeadphoneTargetCurve.harmanInEar2019.name), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text(HeadphoneTargetCurve.harmanInEar2019.name));
      await tester.pumpAndSettle();

      // Opening the selector must not be read as a band drag on the chart.
      expect(gainChanges, 0);

      // None + the three bundled curves.
      expect(find.text('None'), findsOneWidget);
      for (final curve in HeadphoneTargetCurve.all) {
        expect(find.text(curve.name), findsWidgets);
      }

      await tester.tap(
        find
            .widgetWithText(
              CheckedPopupMenuItem<HeadphoneTargetCurve?>,
              HeadphoneTargetCurve.harmanOverEar2018.name,
            )
            .last,
      );
      await tester.pumpAndSettle();

      expect(selected, HeadphoneTargetCurve.harmanOverEar2018);
      expect(find.text(HeadphoneTargetCurve.harmanOverEar2018.name),
          findsOneWidget);
    });

    testWidgets('fits a fixed-height host without overflowing', (tester) async {
      // eq_sheet_shell gives the chart a 52 px slot inside a 64 px container;
      // the overlaid selector must not add height to that slot.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black12),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: EqCurveVisualizer(
                      gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
                      activeColor: Colors.cyan,
                      height: 52,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(EqCurveVisualizer)).height,
        52,
      );
    });

    testWidgets('hides the target-curve selector when disabled',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 80,
                child: EqCurveVisualizer(
                  gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
                  activeColor: Colors.cyan,
                  height: 80,
                  showTargetCurveSelector: false,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(PopupMenuButton<HeadphoneTargetCurve?>), findsNothing);
    });

    testWidgets('renders properly under RTL directionality', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SizedBox(
                width: 320,
                height: 80,
                child: EqCurveVisualizer(
                  gains: [1.0, 2.0, 3.0, 4.0, 5.0],
                  activeColor: Colors.teal,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(EqCurveVisualizer), findsOneWidget);
    });
  });
}
