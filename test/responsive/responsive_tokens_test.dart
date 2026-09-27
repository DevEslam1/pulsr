import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/responsive/responsive_values.dart';
import 'package:pulsr/core/responsive/responsive_typography.dart';
import 'package:pulsr/core/responsive/responsive_motion.dart';
import 'package:pulsr/core/responsive/responsive_sheet.dart';

void main() {
  group('Responsive Tokens & Typography', () {
    testWidgets('ResponsiveValues resolves correctly based on context', (tester) async {
      late double valueCompact;
      late double valueMedium;
      late double valueExpanded;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Builder(
            builder: (context) {
              valueCompact = context.responsive.value(
                compact: 10.0,
                medium: 20.0,
                expanded: 30.0,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(768, 1024)),
          child: Builder(
            builder: (context) {
              valueMedium = context.responsive.value(
                compact: 10.0,
                medium: 20.0,
                expanded: 30.0,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1024, 768)),
          child: Builder(
            builder: (context) {
              valueExpanded = context.responsive.value(
                compact: 10.0,
                medium: 20.0,
                expanded: 30.0,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(valueCompact, 10.0);
      expect(valueMedium, 20.0);
      expect(valueExpanded, 30.0);
    });

    testWidgets('PulsrTextScaleScope clamps text scaler between 0.85 and 1.5', (tester) async {
      late double scaledSizeLow;
      late double scaledSizeHigh;

      // Extremely low system scaling (0.5x)
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(0.5)),
          child: PulsrTextScaleScope(
            child: Builder(
              builder: (context) {
                scaledSizeLow = MediaQuery.textScalerOf(context).scale(100.0);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      // Extremely high system scaling (3.0x)
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(3.0)),
          child: PulsrTextScaleScope(
            child: Builder(
              builder: (context) {
                scaledSizeHigh = MediaQuery.textScalerOf(context).scale(100.0);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      // Clamped between 85.0 and 150.0
      expect(scaledSizeLow, 85.0);
      expect(scaledSizeHigh, 150.0);
    });

    testWidgets('PulsrResponsiveMotion scales duration and distance', (tester) async {
      late Duration durationCompact;
      late Duration durationLarge;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Builder(
            builder: (context) {
              durationCompact = context.responsiveMotion.ms(200);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1440, 900)),
          child: Builder(
            builder: (context) {
              durationLarge = context.responsiveMotion.ms(200);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(durationCompact, const Duration(milliseconds: 200));
      expect(durationLarge.inMilliseconds, greaterThanOrEqualTo(230));
    });

    testWidgets('PulsrResponsiveSheetContainer renders dialog mode correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PulsrResponsiveSheetContainer(
              isDialogMode: true,
              title: Text('Test Dialog'),
              child: Text('Content'),
            ),
          ),
        ),
      );

      expect(find.text('Test Dialog'), findsOneWidget);
      expect(find.text('Content'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });
  });
}
