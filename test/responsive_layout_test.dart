import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/adaptive.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme_scaffold.dart';

void main() {
  group('Adaptive responsive metrics across screen sizes', () {
    testWidgets('Validates scale factors across small, standard, large, and tablet screens',
        (tester) async {
      const testSizes = [
        Size(320, 568),  // Small phone (iPhone SE 1st gen)
        Size(360, 640),  // Compact Android
        Size(390, 844),  // Standard phone baseline
        Size(412, 915),  // Pixel 7
        Size(430, 932),  // iPhone 14/15 Pro Max
        Size(768, 1024), // Tablet portrait
        Size(1024, 768), // Tablet landscape
        Size(1440, 900), // Desktop / large window
      ];

      for (final size in testSizes) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                // Verify scale factors are strictly bounded
                expect(context.scaleFactorW, inInclusiveRange(0.80, 1.35));
                expect(context.scaleFactorH, inInclusiveRange(0.70, 1.30));
                expect(context.scaleFactorR, inInclusiveRange(0.70, 1.35));
                expect(context.fontScale, inInclusiveRange(0.80, 1.35));

                // Verify responsive dimension scaling helpers
                expect(context.rw(100), greaterThan(0));
                expect(context.rh(100), greaterThan(0));
                expect(context.rsp(16), greaterThan(0));
                expect(context.rr(12), greaterThan(0));

                // Verify page padding adapts properly
                expect(context.pagePadding, anyOf(equals(12.0), equals(16.0), equals(24.0), equals(32.0)));

                // Verify PlayerThemeMetrics calculations
                final metrics = PlayerThemeMetrics.calculate(
                  context,
                  BoxConstraints(maxWidth: size.width, maxHeight: size.height),
                );
                expect(metrics.heightRatio, inInclusiveRange(0.55, 1.25));
                expect(metrics.pillBarWidth, greaterThan(0));
                expect(metrics.pillBarWidth, lessThanOrEqualTo(size.width));
                expect(metrics.pillBarHeight, inInclusiveRange(30.0, 60.0));

                // Verify safe artwork sizing never overflows available height/width
                final safeArtSmall = PlayerThemeMetrics.safeArtworkSize(
                  availableWidth: 150,
                  availableHeight: 120,
                  isTablet: context.isTablet,
                );
                expect(safeArtSmall, lessThanOrEqualTo(120));
                expect(safeArtSmall, greaterThanOrEqualTo(0));

                final safeArtLarge = PlayerThemeMetrics.safeArtworkSize(
                  availableWidth: 600,
                  availableHeight: 500,
                  isTablet: context.isTablet,
                );
                expect(safeArtLarge, lessThanOrEqualTo(500));

                return const Scaffold(
                  body: Center(child: Text('Responsive test passed')),
                );
              },
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(find.text('Responsive test passed'), findsOneWidget);
      }
    });

    testWidgets('Safe artwork size handles zero and negative constraints gracefully', (tester) async {
      final safeArtZero = PlayerThemeMetrics.safeArtworkSize(
        availableWidth: 0,
        availableHeight: 0,
        isTablet: false,
      );
      expect(safeArtZero, equals(0.0));

      final safeArtNegative = PlayerThemeMetrics.safeArtworkSize(
        availableWidth: -10,
        availableHeight: 200,
        isTablet: false,
      );
      expect(safeArtNegative, equals(0.0));
    });
  });
}
