import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/responsive/responsive_values.dart';
import 'package:pulsr/features/home/presentation/widgets/home_card_metrics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({double title, double carousel, double cardWidth})> measure(
    WidgetTester tester, {
    required Size size,
    double textScale = 1.0,
    bool isTablet = false,
  }) async {
    late double title;
    late double carousel;
    late double cardWidth;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: Builder(
              builder: (context) {
                title = scaledTitleBoxHeight(context);
                carousel = scaledCarouselHeight(context, isTablet);
                cardWidth = context.responsive
                    .value(compact: 138.0, medium: 150.0, expanded: 158.0);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    return (title: title, carousel: carousel, cardWidth: cardWidth);
  }

  group('scaledTitleBoxHeight', () {
    testWidgets('returns the 34px base on a phone at default text scale',
        (tester) async {
      final m = await measure(tester, size: const Size(390, 844));
      expect(m.title, 34.0);
    });

    testWidgets('returns the s38 base on a tablet', (tester) async {
      final m = await measure(tester, size: const Size(800, 800));
      expect(m.title, AppSpacing.s38);
    });

    testWidgets('clamps at 78px under very large Dynamic Type', (tester) async {
      final m = await measure(
        tester,
        size: const Size(390, 844),
        textScale: 3.0,
      );
      expect(m.title, 78.0);
    });
  });

  group('scaledCarouselHeight', () {
    testWidgets('composes card width, title box, artist line and padding',
        (tester) async {
      final m = await measure(tester, size: const Size(390, 844));
      final artistHeight = 14.0 * 1.35;
      expect(
        m.carousel,
        closeTo(
          m.cardWidth +
              AppSpacing.xs +
              m.title +
              AppSpacing.s2 +
              artistHeight +
              12.0,
          0.001,
        ),
      );
    });

    testWidgets('uses the tablet title box and medium card width',
        (tester) async {
      final m = await measure(
        tester,
        size: const Size(800, 800),
        isTablet: true,
      );
      final artistHeight = 14.0 * 1.35;
      expect(m.cardWidth, 150.0);
      expect(
        m.carousel,
        closeTo(
          m.cardWidth +
              AppSpacing.xs +
              AppSpacing.s38 +
              AppSpacing.s2 +
              artistHeight +
              12.0,
          0.001,
        ),
      );
    });

    testWidgets('grows with Dynamic Type without clipping', (tester) async {
      final m = await measure(
        tester,
        size: const Size(390, 844),
        textScale: 3.0,
      );
      final artistHeight = 42.0 * 1.35;
      expect(m.title, 78.0);
      expect(
        m.carousel,
        closeTo(
          m.cardWidth +
              AppSpacing.xs +
              78.0 +
              AppSpacing.s2 +
              artistHeight +
              12.0,
          0.001,
        ),
      );
    });
  });
}
