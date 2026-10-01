import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/responsive/breakpoints.dart';
import 'package:pulsr/core/utils/adaptive.dart';

void main() {
  group('PulsrBreakpoint Tiers', () {
    test('fromWidth maps correctly to all 4 tiers', () {
      expect(PulsrBreakpoint.fromWidth(0), PulsrBreakpoint.compact);
      expect(PulsrBreakpoint.fromWidth(360), PulsrBreakpoint.compact);
      expect(PulsrBreakpoint.fromWidth(599.9), PulsrBreakpoint.compact);

      expect(PulsrBreakpoint.fromWidth(600), PulsrBreakpoint.medium);
      expect(PulsrBreakpoint.fromWidth(768), PulsrBreakpoint.medium);
      expect(PulsrBreakpoint.fromWidth(839.9), PulsrBreakpoint.medium);

      expect(PulsrBreakpoint.fromWidth(840), PulsrBreakpoint.expanded);
      expect(PulsrBreakpoint.fromWidth(1024), PulsrBreakpoint.expanded);
      expect(PulsrBreakpoint.fromWidth(1199.9), PulsrBreakpoint.expanded);

      expect(PulsrBreakpoint.fromWidth(1200), PulsrBreakpoint.large);
      expect(PulsrBreakpoint.fromWidth(1920), PulsrBreakpoint.large);
    });

    test('PulsrBreakpoint comparison operators work correctly', () {
      expect(PulsrBreakpoint.compact < PulsrBreakpoint.medium, isTrue);
      expect(PulsrBreakpoint.medium < PulsrBreakpoint.expanded, isTrue);
      expect(PulsrBreakpoint.expanded < PulsrBreakpoint.large, isTrue);

      expect(PulsrBreakpoint.large > PulsrBreakpoint.expanded, isTrue);
      expect(PulsrBreakpoint.expanded >= PulsrBreakpoint.medium, isTrue);
      expect(PulsrBreakpoint.medium <= PulsrBreakpoint.medium, isTrue);
      expect(PulsrBreakpoint.compact >= PulsrBreakpoint.medium, isFalse);
    });

    testWidgets('Context extension detects breakpoints accurately',
        (tester) async {
      late PulsrBreakpoint capturedBreakpoint;
      late bool capturedIsCompact;
      late bool capturedIsMedium;
      late bool capturedIsLandscape;

      Widget buildWidget(Size size) {
        return MediaQuery(
          data: MediaQueryData(size: size),
          child: Builder(
            builder: (context) {
              capturedBreakpoint = context.breakpoint;
              capturedIsCompact = context.isCompact;
              capturedIsMedium = context.isMedium;
              capturedIsLandscape = context.isLandscape;
              return const SizedBox.shrink();
            },
          ),
        );
      }

      // Compact Portrait (390 x 844)
      await tester.pumpWidget(buildWidget(const Size(390, 844)));
      expect(capturedBreakpoint, PulsrBreakpoint.compact);
      expect(capturedIsCompact, isTrue);
      expect(capturedIsMedium, isFalse);
      expect(capturedIsLandscape, isFalse);

      // Compact Landscape Phone (844 x 390)
      // Note: width 844dp maps to expanded tier, orientation is landscape
      await tester.pumpWidget(buildWidget(const Size(844, 390)));
      expect(capturedBreakpoint, PulsrBreakpoint.expanded);
      expect(capturedIsLandscape, isTrue);

      // Medium Tablet Portrait (768 x 1024)
      await tester.pumpWidget(buildWidget(const Size(768, 1024)));
      expect(capturedBreakpoint, PulsrBreakpoint.medium);
      expect(capturedIsMedium, isTrue);
      expect(capturedIsLandscape, isFalse);

      // Large Desktop (1440 x 900)
      await tester.pumpWidget(buildWidget(const Size(1440, 900)));
      expect(capturedBreakpoint, PulsrBreakpoint.large);
      expect(capturedIsLandscape, isTrue);
    });
  });
}
