import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/responsive/responsive_values.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
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
        theme: AuraTheme.darkTheme,
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
    testWidgets('returns the 20px single-line base on a phone at default scale',
        (tester) async {
      final m = await measure(tester, size: const Size(390, 844));
      expect(m.title, 20.0);
    });

    testWidgets('returns the 22px single-line base on a tablet',
        (tester) async {
      final m = await measure(tester, size: const Size(800, 800));
      expect(m.title, 22.0);
    });

    testWidgets('scales cleanly at 200% text scale without clipping',
        (tester) async {
      final m = await measure(
        tester,
        size: const Size(390, 844),
        textScale: 2.0,
      );
      expect(m.title, 40.0);
    });

    testWidgets('clamps at 64px under very large Dynamic Type', (tester) async {
      final m = await measure(
        tester,
        size: const Size(800, 800),
        textScale: 3.5,
      );
      expect(m.title, 64.0);
    });
  });

  group('scaledCarouselHeight', () {
    testWidgets('composes card width, title box, artist line and padding',
        (tester) async {
      final m = await measure(tester, size: const Size(390, 844));
      final artistHeight = AppFontSize.caption * 1.4;
      expect(
        m.carousel,
        closeTo(
          m.cardWidth +
              AppSpacing.xs +
              m.title +
              AppSpacing.s2 +
              artistHeight +
              AppSpacing.sm,
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
      final artistHeight = AppFontSize.caption * 1.4;
      expect(m.cardWidth, 150.0);
      expect(
        m.carousel,
        closeTo(
          m.cardWidth +
              AppSpacing.xs +
              22.0 +
              AppSpacing.s2 +
              artistHeight +
              AppSpacing.sm,
          0.001,
        ),
      );
    });

    testWidgets('grows with 200% and 300% Dynamic Type without clipping',
        (tester) async {
      final m200 = await measure(
        tester,
        size: const Size(390, 844),
        textScale: 2.0,
      );
      final artist200 = (AppFontSize.caption * 2.0) * 1.4;
      expect(m200.title, 40.0);
      expect(
        m200.carousel,
        closeTo(
          m200.cardWidth +
              AppSpacing.xs +
              40.0 +
              AppSpacing.s2 +
              artist200 +
              AppSpacing.sm,
          0.001,
        ),
      );

      final m300 = await measure(
        tester,
        size: const Size(390, 844),
        textScale: 3.0,
      );
      final artist300 = (AppFontSize.caption * 3.0) * 1.4;
      expect(m300.title, 60.0);
      expect(
        m300.carousel,
        closeTo(
          m300.cardWidth +
              AppSpacing.xs +
              60.0 +
              AppSpacing.s2 +
              artist300 +
              AppSpacing.sm,
          0.001,
        ),
      );
    });
  });

  group('HomeCardPlayBadge', () {
    testWidgets('renders play icon when idle and equalizer bars when playing',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.darkTheme,
          home: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Column(
                children: [
                  HomeCardPlayBadge(isCurrent: false, isPlaying: false),
                  HomeCardPlayBadge(isCurrent: true, isPlaying: true),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byKey(const ValueKey('eq')), findsOneWidget);
    });
  });
}
