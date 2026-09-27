// test/features/player/milkdrop_renderer_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/milkdrop_preset.dart';
import 'package:pulsr/features/player/presentation/widgets/visualizer/milkdrop_renderer.dart';

void main() {
  group('MilkdropRenderer Tests', () {
    const testPreset = MilkdropPreset(
      name: 'Cosmic Nebula',
      decay: 0.98,
      waveR: 0.8,
      waveG: 0.2,
      waveB: 0.9,
      rot: 0.05,
      zoom: 1.02,
      warp: 0.1,
    );

    testWidgets('renders Canvas fallback when shader is null without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: MilkdropRenderer(
                shader: null,
                data: [0.1, 0.5, 0.9, 0.3, 0.4, 0.2, 0.8, 0.6],
                color: Colors.purple,
                preset: testPreset,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(MilkdropRenderer), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MilkdropRenderer),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    });

    testWidgets('honors forceCanvasFallback flag', (tester) async {
      const renderer = MilkdropRenderer(
        data: [0.2, 0.4],
        color: Colors.cyan,
        preset: testPreset,
        forceCanvasFallback: true,
      );

      expect(renderer.isFallback, isTrue);
    });

    test('MilkdropCanvasPainter shouldRepaint always returns true for animation', () {
      final painter = MilkdropCanvasPainter(
        data: const [0.5, 0.5],
        color: Colors.blue,
        preset: testPreset,
      );
      expect(painter.shouldRepaint(painter), isTrue);
    });
  });
}
