// test/features/player/eq_curve_visualizer_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      await tester.pump();
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
