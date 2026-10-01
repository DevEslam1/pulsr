import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/responsive/layout_delegate.dart';

void main() {
  group('PulsrLayoutDelegate', () {
    testWidgets('Standard Phone Portrait (390 x 844) uses bottomNav',
        (tester) async {
      late PulsrLayoutDelegate delegate;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Builder(
            builder: (context) {
              delegate = PulsrLayoutDelegate.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(delegate.layoutMode, ShellLayoutMode.bottomNav);
      expect(delegate.showRail, isFalse);
      expect(delegate.showSideInspector, isFalse);
      expect(delegate.playerBarHeight, 148.0);
    });

    testWidgets(
        'Landscape Phone (720 x 360) uses bottomNavWide with 56dp player bar',
        (tester) async {
      late PulsrLayoutDelegate delegate;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(720, 360)),
          child: Builder(
            builder: (context) {
              delegate = PulsrLayoutDelegate.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(delegate.layoutMode, ShellLayoutMode.bottomNavWide);
      expect(delegate.showRail, isFalse);
      expect(delegate.showSideInspector, isFalse);
      expect(delegate.playerBarHeight, 56.0);
    });

    testWidgets(
        'Tablet Portrait (768 x 1024) uses sideRailCollapsed with 64dp rail',
        (tester) async {
      late PulsrLayoutDelegate delegate;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(768, 1024)),
          child: Builder(
            builder: (context) {
              delegate = PulsrLayoutDelegate.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(delegate.layoutMode, ShellLayoutMode.sideRailCollapsed);
      expect(delegate.showRail, isTrue);
      expect(delegate.navWidth, 64.0);
      expect(delegate.showSideInspector, isFalse);
      expect(delegate.playerBarHeight, 90.0);
    });

    testWidgets(
        'Tablet Landscape (1024 x 768) uses sideRailExpanded with side inspector',
        (tester) async {
      late PulsrLayoutDelegate delegate;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1024, 768)),
          child: Builder(
            builder: (context) {
              delegate = PulsrLayoutDelegate.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(delegate.layoutMode, ShellLayoutMode.sideRailExpanded);
      expect(delegate.showRail, isTrue);
      expect(delegate.navWidth, 240.0);
      expect(delegate.showSideInspector, isTrue);
      expect(delegate.playerBarHeight, 90.0);
    });

    testWidgets('Large Desktop (1440 x 900) uses sideRailFull with 260dp rail',
        (tester) async {
      late PulsrLayoutDelegate delegate;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1440, 900)),
          child: Builder(
            builder: (context) {
              delegate = PulsrLayoutDelegate.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(delegate.layoutMode, ShellLayoutMode.sideRailFull);
      expect(delegate.showRail, isTrue);
      expect(delegate.navWidth, 260.0);
      expect(delegate.showSideInspector, isTrue);
      expect(delegate.contentMaxWidth, 1400.0);
      expect(delegate.playerBarHeight, 90.0);
    });
  });
}
