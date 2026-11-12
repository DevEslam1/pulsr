// test/responsive/responsive_source_of_truth_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/responsive/breakpoints.dart';
import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';
import 'package:pulsr/core/responsive/pulsr_responsive_tokens.dart';
import 'package:pulsr/core/utils/adaptive.dart';

Widget _buildResponsiveTestHarness({
  required double width,
  required double height,
  required void Function(BuildContext context) onBuild,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, height),
        padding: EdgeInsets.zero,
        viewInsets: EdgeInsets.zero,
      ),
      child: Builder(
        builder: (context) {
          onBuild(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Responsive Single Source of Truth at 600, 720, 840dp', () {
    testWidgets('600x960 small tablet portrait agrees across tokens and Adaptive API',
        (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        _buildResponsiveTestHarness(
          width: 600,
          height: 960,
          onBuild: (ctx) => capturedContext = ctx,
        ),
      );

      final ctx = capturedContext;
      final vp = PulsrViewport.of(ctx);

      expect(vp.deviceClass, PulsrDeviceClass.tablet);
      expect(Adaptive.isTablet(ctx), isTrue);
      expect(vp.sizeClass, PulsrBreakpoint.medium);
      expect(Adaptive.windowOf(ctx), WindowClass.medium);
      expect(Adaptive.pagePadding(ctx), 24.0);
      expect(vp.pagePadding, 24.0);
      expect(PulsrLayoutMetrics.contentMaxWidth(ctx), 720.0);
      expect(Adaptive.trackGridColumns(ctx), 2);
    });

    testWidgets('720x1024 tablet agrees across tokens and Adaptive API',
        (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        _buildResponsiveTestHarness(
          width: 720,
          height: 1024,
          onBuild: (ctx) => capturedContext = ctx,
        ),
      );

      final ctx = capturedContext;
      final vp = PulsrViewport.of(ctx);

      expect(vp.deviceClass, PulsrDeviceClass.tablet);
      expect(Adaptive.isTablet(ctx), isTrue);
      expect(vp.sizeClass, PulsrBreakpoint.medium);
      expect(Adaptive.windowOf(ctx), WindowClass.medium);
      expect(Adaptive.pagePadding(ctx), 24.0);
      expect(vp.pagePadding, 24.0);
      expect(PulsrLayoutMetrics.contentMaxWidth(ctx), 720.0);
      expect(Adaptive.trackGridColumns(ctx), 2);
    });

    testWidgets('840x1280 large tablet portrait enters expanded tier consistently',
        (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        _buildResponsiveTestHarness(
          width: 840,
          height: 1280,
          onBuild: (ctx) => capturedContext = ctx,
        ),
      );

      final ctx = capturedContext;
      final vp = PulsrViewport.of(ctx);

      expect(vp.deviceClass, PulsrDeviceClass.tablet);
      expect(Adaptive.isTablet(ctx), isTrue);
      expect(vp.sizeClass, PulsrBreakpoint.expanded);
      expect(Adaptive.windowOf(ctx), WindowClass.expanded);
      expect(Adaptive.pagePadding(ctx), 24.0);
      expect(vp.pagePadding, 24.0);
      expect(PulsrLayoutMetrics.contentMaxWidth(ctx), 860.0);
      expect(Adaptive.trackGridColumns(ctx), 2);
      expect(ctx.isTwoPanePlaylist, isFalse); // Portrait aspect ratio
    });

    testWidgets('1280x800 tablet landscape enables 2-pane playlist and expanded tier',
        (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        _buildResponsiveTestHarness(
          width: 1280,
          height: 800,
          onBuild: (ctx) => capturedContext = ctx,
        ),
      );

      final ctx = capturedContext;
      final vp = PulsrViewport.of(ctx);

      expect(vp.deviceClass, PulsrDeviceClass.desktop);
      expect(Adaptive.isTablet(ctx), isTrue);
      expect(Adaptive.isTabletLandscape(ctx), isTrue);
      expect(vp.sizeClass, PulsrBreakpoint.large);
      expect(Adaptive.windowOf(ctx), WindowClass.expanded);
      expect(Adaptive.pagePadding(ctx), 32.0);
      expect(ctx.isTwoPanePlaylist, isTrue);
      expect(Adaptive.trackGridColumns(ctx), 3);
    });
  });
}
