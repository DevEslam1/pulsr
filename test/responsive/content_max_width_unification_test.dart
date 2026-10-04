// test/responsive/content_max_width_unification_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/responsive/breakpoints.dart';
import 'package:pulsr/core/responsive/layout_delegate.dart';
import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';
import 'package:pulsr/core/responsive/pulsr_responsive_tokens.dart';

void main() {
  group('contentMaxWidth single source of truth (P1-19)', () {
    const cases = <({Size size, PulsrBreakpoint tier, double expected})>[
      (size: Size(390, 844), tier: PulsrBreakpoint.compact, expected: 640.0),
      (size: Size(768, 1024), tier: PulsrBreakpoint.medium, expected: 720.0),
      (size: Size(1024, 768), tier: PulsrBreakpoint.expanded, expected: 860.0),
      (size: Size(1440, 900), tier: PulsrBreakpoint.large, expected: 1000.0),
    ];

    for (final c in cases) {
      testWidgets('all three sources agree for ${c.tier.name}', (tester) async {
        late double viewportWidth;
        late double metricsWidth;
        late double delegateWidth;

        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(size: c.size),
            child: Builder(
              builder: (context) {
                viewportWidth =
                    PulsrViewport.fromContext(context).contentMaxWidth;
                metricsWidth = PulsrLayoutMetrics.contentMaxWidth(context);
                delegateWidth = PulsrLayoutDelegate.of(context).contentMaxWidth;
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        expect(c.tier.contentMaxWidth, c.expected);
        expect(viewportWidth, c.expected);
        expect(metricsWidth, c.expected);
        expect(delegateWidth, c.expected);
      });
    }
  });

  group('isShortHeight threshold alignment (P1-19)', () {
    testWidgets('medium landscape just above threshold is not short',
        (tester) async {
      late PulsrViewport viewport;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(820, 600)),
          child: Builder(
            builder: (context) {
              viewport = PulsrViewport.fromContext(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(viewport.isShortHeight, isFalse);
    });

    testWidgets('landscape below the shared threshold is short',
        (tester) async {
      late PulsrViewport viewport;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(915, 412)),
          child: Builder(
            builder: (context) {
              viewport = PulsrViewport.fromContext(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(viewport.isShortHeight, isTrue);
      expect(PulsrBreakpoint.shortHeightThreshold, 600.0);
    });
  });
}
