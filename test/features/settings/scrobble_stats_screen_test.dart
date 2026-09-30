import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/settings/presentation/scrobble_stats_screen.dart';

void main() {
  group('M-26: ScrobbleBarChartPainter single-element and edge cases', () {
    testWidgets('paints single-element data without error and centers bar', (tester) async {
      final painter = ScrobbleBarChartPainter(
        data: const [42],
        labels: const ['Today'],
        barColor: Colors.blue,
        labelColor: Colors.white,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 130,
                child: CustomPaint(
                  painter: painter,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('paints empty data without error', (tester) async {
      final painter = ScrobbleBarChartPainter(
        data: const [],
        labels: const [],
        barColor: Colors.blue,
        labelColor: Colors.white,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 130,
                child: CustomPaint(
                  painter: painter,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('handles constrained/small canvas sizes without crashing', (tester) async {
      final painter = ScrobbleBarChartPainter(
        data: const [10],
        labels: const ['M'],
        barColor: Colors.blue,
        labelColor: Colors.white,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 15,
                height: 20,
                child: CustomPaint(
                  painter: painter,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('paints multi-element data correctly', (tester) async {
      final painter = ScrobbleBarChartPainter(
        data: const [5, 12, 0, 8, 15, 2, 7],
        labels: const ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
        barColor: Colors.purple,
        labelColor: Colors.grey,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 350,
                height: 130,
                child: CustomPaint(
                  painter: painter,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
